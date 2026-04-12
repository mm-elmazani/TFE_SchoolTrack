# Guide de contribution — SchoolTrack

Ce document définit les conventions de code, la structure des dossiers, le workflow Git et les procédures de test à respecter pour contribuer au projet SchoolTrack.

---

## Conventions de code

### Langue

| Élément | Langue |
|---------|--------|
| Code source (variables, fonctions, classes) | **Anglais** |
| Commentaires, docstrings, messages d'erreur UI | **Français** |
| Messages de commit | **Français** |
| Documentation (docs/, README) | **Français** |

### Python (Backend FastAPI)

- **Formateur** : `black` (ligne max 88 caractères)
- **Linter** : `ruff`
- **Type hints** obligatoires sur toutes les fonctions publiques
- **Docstrings** au format Google pour les services et routers
- Imports groupés : stdlib → third-party → local (séparés par une ligne vide)

```python
# ✅ Bon
async def get_trip(trip_id: str, db: Session = Depends(get_db)) -> TripResponse:
    """Retourne un voyage par son identifiant.

    Args:
        trip_id: Identifiant UUID du voyage.
        db: Session SQLAlchemy injectée.

    Returns:
        TripResponse avec les données du voyage.

    Raises:
        HTTPException 404 si le voyage n'existe pas.
    """
```

### Dart / Flutter (App mobile)

- **Formateur** : `dart format` (ligne max 80 caractères)
- **Linter** : `flutter_lints` (règles définies dans `analysis_options.yaml`)
- Préférer les `const` constructors quand possible
- Providers : `ChangeNotifier` — garder la logique métier hors des widgets
- Nommage fichiers : `snake_case.dart` · Classes : `PascalCase`

### TypeScript / React (Dashboard)

- **Formateur** : Prettier (config dans `.prettierrc`)
- **Linter** : ESLint
- Composants : `PascalCase.tsx`
- Hooks personnalisés : `useFeatureName.ts`
- Pas de `any` — toujours typer les props et réponses API

---

## Préfixes de commits

Format : `[PREFIXE](scope): description courte en français`

| Préfixe | Usage |
|---------|-------|
| `[FEAT]` | Nouvelle fonctionnalité |
| `[UPDATE]` | Amélioration d'une fonctionnalité existante |
| `[FIX]` | Correction de bug |
| `[TEST]` | Ajout ou modification de tests |
| `[CONFIG]` | Configuration, dépendances, scripts |
| `[DOCS]` | Documentation uniquement |
| `[REFACTOR]` | Refactoring sans changement de comportement |
| `[PERF]` | Optimisation de performance |
| `[SECURITY]` | Correctif ou amélioration de sécurité |

**Scopes courants** : `api`, `react`, `mobile`, `db`, `infra`, `global`

```bash
# ✅ Exemples corrects
[FEAT](api): ajouter endpoint GET /api/v1/trips/{id}/offline-data
[FIX](mobile): corriger la lecture studentCount depuis SQLite local
[TEST](react): tests unitaires StudentListScreen — tri et pagination
[CONFIG](infra): passer Traefik de v3.3 à latest pour compatibilité Docker 29
```

---

## Structure des dossiers

```
TFE_SchoolTrack/
├── backend/
│   ├── app/
│   │   ├── models/         # Un fichier par entité (user.py, trip.py…)
│   │   ├── schemas/        # Pydantic — request/response par domaine
│   │   ├── routers/        # Un fichier par ressource REST
│   │   ├── services/       # Logique métier — pas de SQL direct ici
│   │   ├── dependencies.py # Injection de dépendances FastAPI
│   │   ├── database.py     # Session SQLAlchemy
│   │   └── main.py         # Entrée FastAPI, middlewares, routers
│   ├── migrations/         # Scripts SQL numérotés (001_..., 002_…)
│   └── tests/              # Tests Pytest
│
├── flutter_teacher_app/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── api/        # ApiClient HTTP
│   │   │   ├── database/   # LocalDb SQLite (singleton)
│   │   │   └── services/   # SyncService, HybridIdentityReader
│   │   └── features/
│   │       ├── auth/       # Login, providers auth
│   │       ├── trips/      # Liste voyages, bundle offline
│   │       ├── scan/       # Session de scan, modèles présences
│   │       └── sync/       # Historique synchronisation
│   ├── test/               # Tests unitaires + intégration (flutter test)
│   └── integration_test/   # Tests intégration émulateur Android
│
├── react_dashboard/
│   └── src/
│       ├── features/       # Un dossier par domaine métier
│       │   └── [feature]/
│       │       ├── api/        # Hooks React Query
│       │       ├── screens/    # Pages complètes
│       │       └── __tests__/  # Tests Vitest co-localisés
│       └── shared/
│           ├── components/ # Composants réutilisables
│           └── hooks/      # Hooks génériques
│
└── docs/                   # Documentation technique
```

**Règle** : la logique métier ne doit jamais se trouver dans un composant UI ou une route HTTP — toujours dans un `service/`.

---

## Workflow Git

### Branches

| Branche | Usage |
|---------|-------|
| `main` | Production stable — merge uniquement via PR reviewée |
| `develop` | Intégration continue — base de toutes les features |
| `feature/us-X-Y-description` | Nouvelle US |
| `fix/description-courte` | Correction de bug |

### Procédure

```bash
# 1. Partir de develop à jour
git checkout develop
git pull origin develop

# 2. Créer une branche feature
git checkout -b feature/us-7-2-offline-integration-tests

# 3. Développer, commiter régulièrement
git add fichier1 fichier2
git commit -m "[TEST](mobile): scénario offline-first 50 élèves NFC+QR"

# 4. Pousser et ouvrir une PR vers develop
git push origin feature/us-7-2-offline-integration-tests
```

### Règles

- **Ne jamais committer directement sur `main`**
- Commits atomiques — un commit = une modification cohérente
- **Ne jamais committer** : `.env`, `*.prod`, clés privées, `coverage/`
- Le `pubspec.lock` et `package-lock.json` sont committés (reproductibilité des builds)

---

## Lancer les tests

### Backend (Pytest)

```bash
cd backend
pip install -r requirements.txt
pytest                                  # tous les tests
pytest tests/test_api_trips.py -v       # fichier spécifique
pytest --cov=app --cov-report=html      # avec rapport de couverture
```

Seuil minimal : **80 % de couverture** sur les modules critiques.

### Dashboard React (Vitest)

```bash
cd react_dashboard
npm test                    # mode watch
npm run test:run            # one-shot (CI)
npm run coverage            # rapport HTML
```

### App Flutter — tests unitaires

```bash
cd flutter_teacher_app
flutter test test/          # tous les tests unitaires
flutter test test/services/ # répertoire spécifique
```

### App Flutter — tests d'intégration (US 7.2)

```bash
# Sans émulateur (VM / CI)
flutter test test/integration/offline_sync_test.dart

# Sur émulateur Android (nécessite un device connecté)
flutter test integration_test/offline_sync_test.dart -d <device-id>
```

---

## Zones sensibles (traitement T4)

Toute modification sur les éléments suivants requiert une attention particulière et une validation explicite avant merge :

- `backend/migrations/` — migrations de base de données (irréversibles)
- `backend/app/services/auth_service.py` — authentification et tokens JWT
- `backend/app/services/crypto_service.py` — chiffrement des données
- `flutter_teacher_app/lib/core/database/local_db.dart` — schéma SQLite (migrations versionnées)
- `docker-compose.prod.yml` / `.env.prod` — configuration de production
- Tout endpoint lié aux permissions ou aux rôles

---

## FAQ développement

**Le login renvoie "Not Found" en local ?**  
Vérifier que `voicebox-server.exe` n'occupe pas le port 8000. Le tuer et relancer `docker compose up`.

**Les tests Flutter échouent avec des erreurs SQLite ?**  
S'assurer que `sqfliteFfiInit()` est appelé dans `setUpAll()` et que `LocalDb.testDatabasePath = inMemoryDatabasePath` est défini dans `setUp()`.

**Le build Docker de l'API échoue sur les fichiers de test TypeScript ?**  
Le `tsconfig.app.json` du dashboard React doit exclure `src/**/__tests__/**`. Vérifier que l'exclusion est bien présente.

**Un endpoint renvoie 401 après un rebuild Docker ?**  
Les tokens JWT sont invalidés si `SECRET_KEY` change. Se déconnecter / reconnecter dans l'application.

**Le sync Flutter boucle à l'infini sur des présences "rejected" ?**  
Le backend renvoie les IDs rejetés dans la réponse sync. Le `SyncService` les marque comme `synced` pour éviter la boucle — vérifier que cette logique est bien présente dans `sync_service.dart`.
