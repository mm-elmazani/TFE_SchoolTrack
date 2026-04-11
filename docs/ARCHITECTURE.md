# Architecture SchoolTrack — Diagrammes techniques

Ce document présente les flux critiques de l'application sous forme de diagrammes de séquence et d'état (syntaxe Mermaid).

---

## 1. Vue d'ensemble du système

```mermaid
graph TB
    subgraph Mobile["📱 App mobile (Flutter Android)"]
        Scanner["Scanner QR / NFC"]
        LocalDB["SQLite AES-256"]
        SyncSvc["SyncService"]
    end

    subgraph Web["🖥️ Dashboard (React + Tailwind)"]
        Dashboard["Interface direction"]
    end

    subgraph Backend["⚙️ API (FastAPI · Python 3.13)"]
        API["Routers REST"]
        Scheduler["APScheduler"]
        Services["Services métier"]
    end

    subgraph DB["🗄️ PostgreSQL 16"]
        PG["Base centrale\n(multi-tenant)"]
    end

    Scanner -->|"Scan offline"| LocalDB
    LocalDB -->|"sync HTTPS"| SyncSvc
    SyncSvc -->|"POST /api/sync/attendances"| API
    Dashboard -->|"HTTPS REST"| API
    API --> Services
    Services --> PG
    Scheduler -->|"QR emails, rotation audit"| Services
```

---

## 2. Flux scan offline-first (US 2.2 + US 3.1)

Scénario : l'enseignant télécharge les données du voyage, part en sortie sans réseau, scanne 50 élèves, puis synchronise au retour.

```mermaid
sequenceDiagram
    actor Prof as Enseignant
    participant App as App Flutter
    participant DB as SQLite local
    participant API as FastAPI

    Note over Prof,API: Phase 1 — Téléchargement (avec réseau)
    Prof->>App: Sélectionne le voyage
    App->>API: GET /api/v1/trips/{id}/offline-data
    API-->>App: Bundle (voyage + élèves + checkpoints + assignations)
    App->>DB: saveBundle() — transaction atomique

    Note over Prof,API: Phase 2 — Mode offline (mode avion)
    Prof->>App: Lance la session de scan
    App->>DB: createCheckpoint() → DRAFT (synced_at = NULL)

    loop 50 élèves
        Prof->>App: Scan NFC ou QR
        App->>DB: resolveUid(token_uid, trip_id)
        DB-->>App: OfflineStudent
        App->>DB: saveAttendance() → synced_at = NULL
        App-->>Prof: Feedback sonore + visuel
    end

    Note over Prof,API: Phase 3 — Retour du réseau
    App->>API: POST /api/v1/trips/{id}/checkpoints (clientId)
    API-->>App: CheckpointCreateResult (serverId)
    App->>DB: markCheckpointSynced()

    App->>API: POST /api/sync/attendances (batch ≤500)
    API-->>App: {accepted: [...], duplicate: [...], rejected: [...]}
    App->>DB: markAttendancesSynced(accepted + duplicate + rejected)
    App->>DB: insertSyncHistory(status: SUCCESS)
```

---

## 3. Flux de synchronisation (US 3.1 — détail SyncService)

```mermaid
sequenceDiagram
    participant SP as SyncProvider
    participant SS as SyncService
    participant DB as LocalDb (SQLite)
    participant API as FastAPI

    SP->>SP: Réseau détecté (connectivity_plus)
    SP->>SP: Debounce 2s
    SP->>SS: syncPendingAttendances(deviceId)

    SS->>DB: getPendingCheckpoints()
    DB-->>SS: [checkpoint DRAFT, synced_at IS NULL]

    loop Chaque checkpoint pending
        SS->>API: POST /api/v1/trips/{id}/checkpoints (clientId)
        alt Succès
            API-->>SS: CheckpointCreateResult
            SS->>DB: markCheckpointSynced()
        else Erreur réseau
            SS-->>SS: break — arrêt sync
        end
    end

    SS->>DB: getPendingAttendances()
    DB-->>SS: [attendances, synced_at IS NULL]

    loop Batch de 500
        SS->>API: POST /api/sync/attendances
        alt Succès (HTTP 200)
            API-->>SS: {accepted, duplicate, rejected}
            SS->>DB: markAttendancesSynced(accepted ∪ duplicate ∪ rejected)
        else null (offline)
            SS-->>SS: hadNetworkError=true, break
        else ApiException (422)
            SS-->>SS: totalFailed += batch.length, continue
        end
    end

    SS->>DB: insertSyncHistory(status: SUCCESS|OFFLINE|PARTIAL)
    SS-->>SP: SyncReport
    SP->>SP: Mise à jour UI (statut sync)
```

---

## 4. Cycle de vie d'un token (bracelet NFC / QR)

```mermaid
stateDiagram-v2
    [*] --> AVAILABLE : Enregistrement\n(POST /api/v1/tokens/init)

    AVAILABLE --> ASSIGNED : Assignation à un élève\n(POST /tokens/{id}/assign)
    ASSIGNED --> AVAILABLE : Désassignation\n(POST /tokens/{id}/unassign)
    ASSIGNED --> ASSIGNED : Réassignation\n(POST /tokens/{id}/reassign\nrequiert justification)

    AVAILABLE --> LOST : Signalement perte
    ASSIGNED --> LOST : Signalement perte

    LOST --> [*] : Archivage définitif

    note right of ASSIGNED
        Double assignation possible :
        NFC_PHYSICAL (primaire)
        +
        QR_DIGITAL (secondaire/backup)
    end note
```

---

## 5. Résolution d'identité lors du scan (HybridIdentityReader)

```mermaid
flowchart TD
    Scan["Scan reçu\n(NFC ou QR)"]
    Scan --> TypeQR{Type ?}

    TypeQR -->|"Commence par QRD-"| QRD["QR Digital\nresolveStudentById(uid, tripId)"]
    TypeQR -->|"Autre"| Token["NFC / QR Physique\nresolveUid(token_uid, tripId)"]

    Token --> SA["Cherche dans\nstudent_assignments\n(double assignation)"]
    SA -->|Trouvé| Student["OfflineStudent ✅"]
    SA -->|Non trouvé| Fallback["Fallback : colonne\ntoken_uid de students"]
    Fallback -->|Trouvé| Student
    Fallback -->|Non trouvé| Unknown["Inconnu ❌\nFeedback erreur"]

    QRD -->|Trouvé| Student
    QRD -->|Non trouvé| Unknown

    Student --> Count["countAttendances\n(checkpoint, student)"]
    Count -->|0| First["Premier scan\nscan_sequence = 1 ✅"]
    Count -->|"> 0"| Dup["Doublon détecté\nscan_sequence = N ⚠️"]
```

---

## 6. Flux d'authentification (US 6.1 + 2FA)

```mermaid
sequenceDiagram
    actor User as Utilisateur
    participant App as Client (Flutter / React)
    participant API as FastAPI

    User->>App: Email + mot de passe
    App->>API: POST /api/v1/auth/login

    alt 2FA désactivée
        API-->>App: {access_token, refresh_token}
    else 2FA activée (TOTP App)
        API-->>App: {requires_2fa: true, method: "APP"}
        App-->>User: Saisir code TOTP (6 chiffres)
        User->>App: Code TOTP
        App->>API: POST /api/v1/auth/login (+ totp_code)
        API-->>App: {access_token, refresh_token}
    else 2FA activée (Email OTP)
        API-->>App: {requires_2fa: true, method: "EMAIL"}
        API--)User: Email avec code OTP (Brevo SMTP)
        User->>App: Code email
        App->>API: POST /api/v1/auth/login (+ totp_code)
        API-->>App: {access_token, refresh_token}
    end

    Note over App,API: Toutes les requêtes suivantes
    App->>API: GET /api/v1/... + Authorization: Bearer {access_token}

    alt Token expiré (401)
        App->>API: POST /api/v1/auth/refresh (refresh_token)
        API-->>App: Nouveau access_token
        App->>API: Retry requête initiale
    end
```

---

## 7. Isolation multi-tenant (US 6.6)

```mermaid
graph LR
    subgraph Request["Requête HTTP"]
        JWT["JWT\n(school_id claim)"]
    end

    subgraph Middleware["FastAPI Dependencies"]
        Auth["get_current_user()"]
        School["get_current_school()"]
    end

    subgraph DB["PostgreSQL"]
        Q["WHERE school_id = :sid\n(toutes les requêtes)"]
        T1["École A"]
        T2["École B"]
        T3["École C"]
    end

    JWT --> Auth --> School --> Q
    Q --> T1
    Q --> T2
    Q --> T3

    style T1 fill:#e8f5e9
    style T2 fill:#e3f2fd
    style T3 fill:#fce4ec
```

Chaque token JWT contient le `school_id` de l'utilisateur. Toutes les requêtes SQL filtrent automatiquement par `school_id` via les dépendances FastAPI — aucune donnée d'une école n'est accessible depuis une autre école.

---

## 8. Schéma de base de données (tables principales)

(à compléter)
