# SchoolTrack -- Protection des donnees

> Document public -- version 1.0 (mars 2026)
> Destinataires : equipe projet, assistant admin, jury TFE

---

## 1. Vue d'ensemble

SchoolTrack protege les donnees personnelles des eleves et du personnel
a **trois niveaux** :

```
                       CHIFFREMENT EN TRANSIT
                       (TLS 1.3 / HTTPS)
                              |
     ┌────────────────────────┼────────────────────────┐
     |                        |                        |
  MOBILE                   SERVEUR                  BASE DE
  (Android)                (API)                    DONNEES
     |                        |                        |
  SQLCipher               AES-256-GCM              PostgreSQL
  BDD locale              par colonne              colonnes TEXT
  entierement             (noms, prenoms,          (base64 chiffre)
  chiffree                emails, TOTP)
```

| Couche | Technologie | Ce qui est protege |
|--------|-------------|-------------------|
| En transit | TLS 1.3 (Let's Encrypt via Traefik) | Toutes les communications reseau |
| Au repos -- serveur | AES-256-GCM (colonne par colonne) | Noms, prenoms, emails des eleves ; noms, prenoms, secret 2FA des utilisateurs |
| Au repos -- mobile | SQLCipher (AES-256 sur toute la BDD) | Toutes les donnees synchronisees localement |
| Export | ZIP AES-256 (optionnel) | Fichiers CSV exportes |

---

## 2. Chiffrement au repos -- Backend (AES-256-GCM)

### Principe

Chaque donnee sensible est chiffree **avant** son ecriture en base de donnees
et dechiffree **a la lecture** par l'API. La base PostgreSQL ne contient jamais
les valeurs en clair.

### Comment ca marche

1. L'API recoit une donnee (ex: prenom "Mohamed")
2. Un **nonce aleatoire** de 12 octets est genere (unique a chaque chiffrement)
3. La donnee est chiffree avec AES-256-GCM en utilisant la cle serveur
4. Le resultat (nonce + texte chiffre) est encode en base64
5. La chaine base64 est stockee en PostgreSQL (colonne TEXT)
6. A la lecture, l'API decode le base64, extrait le nonce, dechiffre et renvoie le texte clair

### Colonnes protegees

| Table | Colonnes chiffrees | Colonnes NON chiffrees (volontairement) |
|-------|-------------------|----------------------------------------|
| `students` | `first_name`, `last_name`, `email` | `id`, `photo_url`, `parent_consent` |
| `users` | `first_name`, `last_name`, `totp_secret` | `email` (identifiant de connexion, UNIQUE), `role` |

> **Pourquoi `users.email` n'est pas chiffre ?**
> C'est l'identifiant de connexion. Pour se connecter, l'API doit chercher
> l'utilisateur par email en SQL (`WHERE email = ...`). Une colonne chiffree
> ne permet pas cette recherche. C'est un compromis accepte et documente.

### Securite du chiffrement

- **AES-256-GCM** : standard militaire, utilise par les banques et gouvernements
- **Nonce unique** : chaque chiffrement utilise un nonce aleatoire different,
  donc chiffrer deux fois la meme valeur donne deux resultats differents
- **Integrite** : GCM inclut un tag d'authentification -- toute modification
  du texte chiffre est detectee (protection contre la falsification)
- **Cle secrete** : stockee en variable d'environnement, jamais dans le code source

---

## 3. Chiffrement au repos -- Mobile (SQLCipher)

### Principe

L'application mobile utilise une base de donnees SQLite locale pour fonctionner
**hors connexion** (mode offline-first). Cette base est chiffree integralement
avec SQLCipher (AES-256).

### Fonctionnement

1. Au premier lancement, l'application genere une **cle aleatoire** de 256 bits
2. Cette cle est stockee dans l'**Android Keystore** (coffre-fort materiel du telephone)
3. Toute la base SQLite est chiffree avec cette cle
4. Meme si le fichier `.db` est extrait du telephone, il est illisible sans la cle

### Points importants

- La cle ne quitte **jamais** le telephone
- Les autres applications ne peuvent pas y acceder (sandboxing Android)
- Si le telephone est reinitialise, la cle est perdue mais les donnees
  peuvent etre re-telechargees depuis le serveur
- Le chiffrement est **transparent** : l'application lit et ecrit normalement,
  SQLCipher gere le chiffrement automatiquement

---

## 4. Chiffrement en transit (TLS / HTTPS)

### Principe

Toutes les communications entre les clients (application mobile, navigateur web)
et le serveur passent par HTTPS avec **TLS 1.3 obligatoire** (les versions
anterieures TLS 1.2 et inferieur sont refusees).

### Mise en oeuvre

- **Traefik v3.3** : reverse proxy qui gere les certificats TLS
- **TLS 1.3 impose** : configuration `minVersion: VersionTLS13` dans Traefik
  (fichier `traefik-tls.yml`). Les clients TLS 1.2 sont rejetes.
- **Let's Encrypt** : certificats gratuits, renouveles automatiquement
- **Redirection HTTP -> HTTPS** : toute connexion HTTP est automatiquement
  redirigee vers HTTPS
- En developpement : certificats auto-signes (pas Let's Encrypt)

---

## 5. Export CSV protege (ZIP AES-256)

L'endpoint d'export des assignations de bracelets offre deux modes :

| Mode | URL | Format |
|------|-----|--------|
| Sans protection | `GET /api/v1/trips/{id}/assignments/export` | CSV brut (text/csv) |
| Avec protection | `GET /api/v1/trips/{id}/assignments/export?password=MonMotDePasse` | ZIP AES-256 |

Le fichier ZIP est chiffre avec **WinZip AES-256** : il faut le mot de passe
pour l'ouvrir. Compatible avec 7-Zip, WinRAR, et les outils ZIP standard.

---

## 6. Authentification et acces

| Mecanisme | Detail |
|-----------|--------|
| Mots de passe | Haches avec bcrypt (cout 12) -- jamais stockes en clair |
| JWT | Tokens signes HS256, expiration 30 min (access) / 24h (refresh) |
| 2FA | TOTP (Google Authenticator, Authy) -- optionnel par utilisateur |
| Verrouillage | Compte bloque 15 min apres 5 tentatives echouees |
| Roles | DIRECTION, TEACHER, OBSERVER, ADMIN_TECH -- acces controle par endpoint |
| Audit | Chaque action sensible est enregistree (qui, quoi, quand, IP) |

---

## 7. Resume : que se passe-t-il si...

| Scenario | Protection |
|----------|-----------|
| Quelqu'un intercepte le trafic reseau | TLS 1.3 -- les donnees sont chiffrees en transit |
| Un attaquant accede a la base PostgreSQL | AES-256-GCM -- les colonnes PII sont illisibles |
| Un telephone est vole/perdu | SQLCipher + Android Keystore -- la BDD locale est chiffree |
| Un fichier CSV exporte est intercepte | ZIP AES-256 -- protege par mot de passe (si active) |
| Quelqu'un tente de forcer un mot de passe | Verrouillage apres 5 tentatives + bcrypt (lent a forcer) |
| Un utilisateur non autorise tente d'acceder | Controle de role JWT -- acces refuse |

---

## 8. Conformite RGPD

- **Minimisation** : seules les donnees necessaires sont collectees
- **Chiffrement** : donnees personnelles chiffrees au repos et en transit
- **Consentement** : champ `parent_consent` pour le consentement parental
- **Audit** : journal d'audit complet (table `audit_logs`, retention 12 mois)
- **Droit d'acces** : export JSON complet des donnees d'un eleve (`GET /students/{id}/data-export`)
- **Droit de rectification** : modification des donnees via `PUT /students/{id}`
- **Droit a l'effacement** : suppression logique (soft delete) avec tracabilite
- **Anonymisation** : les identifiants de bracelets (`token_uid`) sont anonymes

> Document complet : voir `docs/PRIVACY-POLICY.md`
