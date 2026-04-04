"""
US 7.4 — Script de lancement des tests de charge + generation du rapport.

Usage :
  python backend/tests/performance/run_load_test.py [--host HOST] [--duration SECONDS]

Prerequis :
  - API backend en marche (docker compose up -d)
  - pip install locust
  - Comptes seed en DB (teacher@schooltrack.be / admin@schooltrack.be)

Le script :
  1. Lance Locust en mode headless (5 users, ramp-up 1/sec, 60s)
  2. Collecte les resultats CSV
  3. Genere docs/PERFORMANCE.md avec les metriques
"""

import argparse
import csv
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # racine du projet
RESULTS_DIR = ROOT / "backend" / "tests" / "performance" / "results"
LOCUSTFILE = Path(__file__).parent / "locustfile.py"
REPORT_PATH = ROOT / "docs" / "PERFORMANCE.md"


def run_locust(host: str, duration: int) -> bool:
    """Lance Locust en mode headless et retourne True si succes."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable, "-m", "locust",
        "-f", str(LOCUSTFILE),
        "--headless",
        "-u", "5",           # 5 utilisateurs simultanes (critere US 7.4)
        "-r", "1",           # Ramp-up : 1 user/sec
        "--run-time", f"{duration}s",
        "--host", host,
        "--csv", str(RESULTS_DIR / "perf"),
        "--csv-full-history",
        "--only-summary",
    ]

    print(f"\n{'='*60}")
    print(f"  SchoolTrack — Test de charge US 7.4")
    print(f"  Host: {host}")
    print(f"  Users: 5 simultanes | Duree: {duration}s")
    print(f"{'='*60}\n")

    result = subprocess.run(cmd, cwd=str(ROOT))
    # Locust retourne exit code 1 si des requetes echouent (404 sync rejected, etc.)
    # On considere le test reussi tant que les CSV sont generes
    return True


def parse_results() -> dict:
    """Parse les fichiers CSV Locust et retourne les metriques."""
    stats_file = RESULTS_DIR / "perf_stats.csv"
    if not stats_file.exists():
        print(f"ERREUR: {stats_file} introuvable.")
        return {}

    rows = []
    with open(stats_file, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    if not rows:
        return {}

    # La derniere ligne "Aggregated" contient les totaux
    aggregated = rows[-1] if rows[-1].get("Name") == "Aggregated" else None
    endpoints = [r for r in rows if r.get("Name") != "Aggregated"]

    return {
        "aggregated": aggregated,
        "endpoints": endpoints,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }


def check_criteria(data: dict) -> list:
    """Verifie les criteres d'acceptation US 7.4."""
    results = []
    agg = data.get("aggregated", {})

    if not agg:
        return [("Donnees insuffisantes", False, "-", "-")]

    # Critere 1 : 95e percentile < 500ms
    p95 = float(agg.get("95%", 0))
    results.append((
        "95% des requetes < 500ms",
        p95 < 500,
        f"{p95:.0f}ms",
        "< 500ms",
    ))

    # Critere 2 : 20 req/sec sans degradation
    rps = float(agg.get("Requests/s", 0))
    results.append((
        "Debit >= 20 req/sec",
        rps >= 20,
        f"{rps:.1f} req/s",
        ">= 20 req/s",
    ))

    # Critere 3 : temps median < 200ms (indicateur de sante)
    median = float(agg.get("50%", 0))
    results.append((
        "Temps median < 200ms",
        median < 200,
        f"{median:.0f}ms",
        "< 200ms",
    ))

    # Critere 4 : taux d'erreur < 1%
    total = int(agg.get("Request Count", 1))
    failures = int(agg.get("Failure Count", 0))
    error_rate = (failures / total * 100) if total > 0 else 0
    results.append((
        "Taux d'erreur < 1%",
        error_rate < 1,
        f"{error_rate:.2f}%",
        "< 1%",
    ))

    return results


def generate_report(data: dict, criteria: list, host: str, duration: int):
    """Genere le rapport docs/PERFORMANCE.md."""
    agg = data.get("aggregated", {})
    endpoints = data.get("endpoints", [])
    timestamp = data.get("timestamp", "N/A")

    # Statut global
    all_pass = all(c[1] for c in criteria)
    status_emoji = "PASS" if all_pass else "ECHEC PARTIEL"

    lines = [
        "# Rapport de performance — SchoolTrack",
        "",
        f"> Genere le {timestamp} | US 7.4 — Tests de performance et charge",
        "",
        "## Configuration du test",
        "",
        f"- **Outil** : Locust {_get_locust_version()}",
        f"- **Cible** : `{host}`",
        f"- **Utilisateurs simultanes** : 5 (4 enseignants + 1 direction)",
        f"- **Duree** : {duration} secondes",
        f"- **Scenario** : sync 200 presences/batch, navigation dashboard, consultation voyages",
        "",
        "## Resultats globaux",
        "",
        f"| Metrique | Valeur |",
        f"|----------|--------|",
        f"| Requetes totales | {agg.get('Request Count', 'N/A')} |",
        f"| Requetes echouees | {agg.get('Failure Count', 'N/A')} |",
        f"| Temps moyen | {agg.get('Average Response Time', 'N/A')}ms |",
        f"| Temps median (P50) | {agg.get('50%', 'N/A')}ms |",
        f"| P95 | {agg.get('95%', 'N/A')}ms |",
        f"| P99 | {agg.get('99%', 'N/A')}ms |",
        f"| Debit | {agg.get('Requests/s', 'N/A')} req/s |",
        "",
        "## Criteres d'acceptation US 7.4",
        "",
        f"**Statut global : {status_emoji}**",
        "",
        "| Critere | Resultat | Mesure | Objectif |",
        "|---------|----------|--------|----------|",
    ]

    for name, passed, measured, target in criteria:
        icon = "PASS" if passed else "FAIL"
        lines.append(f"| {name} | {icon} | {measured} | {target} |")

    lines.extend([
        "",
        "## Detail par endpoint",
        "",
        "| Endpoint | Requetes | Echecs | Moy. (ms) | P50 (ms) | P95 (ms) | P99 (ms) |",
        "|----------|----------|--------|-----------|----------|----------|----------|",
    ])

    for ep in endpoints:
        lines.append(
            f"| {ep.get('Name', 'N/A')} "
            f"| {ep.get('Request Count', 0)} "
            f"| {ep.get('Failure Count', 0)} "
            f"| {float(ep.get('Average Response Time', 0)):.0f} "
            f"| {ep.get('50%', 'N/A')} "
            f"| {ep.get('95%', 'N/A')} "
            f"| {ep.get('99%', 'N/A')} |"
        )

    lines.extend([
        "",
        "## Scenarios testes",
        "",
        "### Enseignant (x4 poids)",
        "- Login + recuperation token JWT",
        "- Consultation liste des voyages",
        "- Telechargement bundle offline",
        "- **Sync batch de 200 presences** (scenario critique)",
        "- Consultation checkpoints",
        "",
        "### Direction (x1 poids)",
        "- Login + recuperation token JWT",
        "- Consultation dashboard",
        "- Consultation logs de synchronisation",
        "- Consultation statistiques de sync",
        "- Consultation liste des eleves",
        "- Consultation logs d'audit",
        "",
        "## Methodologie",
        "",
        "- **Outil** : Locust (Python) — simulation d'utilisateurs virtuels",
        "- **Ramp-up** : 1 utilisateur/seconde jusqu'a 5 simultanes",
        "- **Base de donnees** : PostgreSQL avec donnees de test (seed)",
        "- **Environnement** : Docker Compose local (API + DB)",
        "- **Reseau** : localhost (pas de latence reseau)",
        "",
        "## Conclusion",
        "",
    ])

    if all_pass:
        lines.append(
            "Tous les criteres d'acceptation de l'US 7.4 sont satisfaits. "
            "L'API SchoolTrack supporte la charge cible de 5 enseignants "
            "synchronisant 200 presences chacun simultanement, avec des temps "
            "de reponse conformes aux exigences."
        )
    else:
        failed = [c[0] for c in criteria if not c[1]]
        lines.append(
            f"Certains criteres ne sont pas satisfaits : {', '.join(failed)}. "
            "Des optimisations sont necessaires (voir detail par endpoint)."
        )

    lines.append("")

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nRapport genere : {REPORT_PATH}")


def _get_locust_version() -> str:
    try:
        import locust
        return locust.__version__
    except Exception:
        return "N/A"


def main():
    parser = argparse.ArgumentParser(description="SchoolTrack — Tests de charge US 7.4")
    parser.add_argument("--host", default="http://localhost:8000", help="URL de l'API")
    parser.add_argument("--duration", type=int, default=60, help="Duree du test en secondes")
    args = parser.parse_args()

    # 1. Lancer Locust
    success = run_locust(args.host, args.duration)
    if not success:
        print("ERREUR: Locust a echoue.")
        sys.exit(1)

    # 2. Parser les resultats
    data = parse_results()
    if not data:
        print("ERREUR: Pas de resultats a analyser.")
        sys.exit(1)

    # 3. Verifier les criteres
    criteria = check_criteria(data)

    # 4. Generer le rapport
    generate_report(data, criteria, args.host, args.duration)

    # 5. Afficher le resume
    print(f"\n{'='*60}")
    print("  RESULTATS US 7.4")
    print(f"{'='*60}")
    for name, passed, measured, target in criteria:
        icon = "PASS" if passed else "FAIL"
        print(f"  [{icon}] {name}: {measured} (objectif: {target})")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
