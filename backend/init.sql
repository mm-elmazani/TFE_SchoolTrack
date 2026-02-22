-- ============================================================================
-- SCHÉMA BASE DE DONNÉES - SchoolTrack v4.2
-- ============================================================================
-- Projet: SchoolTrack - Système de gestion de présence scolaire
-- Auteur: Mohamed Mokhtar El Mazani
-- Version: 4.2 (15 février 2026)
-- Note: Tables réordonnées pour respecter les dépendances FK
-- ============================================================================

-- Extension pour les UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- TABLE: students - Élèves de l'établissement
-- ----------------------------------------------------------------------------
CREATE TABLE students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),                    -- Pour envoi QR Code digital
    photo_url VARCHAR(500),                -- URL photo élève (optionnel)
    parent_consent BOOLEAN DEFAULT FALSE,  -- Consentement parental RGPD
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Note v4.1: Champ 'uid' SUPPRIMÉ (remplacé par table assignments)
-- Note v4.2: Champ 'class' SUPPRIMÉ (normalisation complète via tables classes/class_students)


-- ----------------------------------------------------------------------------
-- TABLE: users - Utilisateurs du système (enseignants, direction, admin)
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,    -- Bcrypt hash (coût 12)
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) NOT NULL,              -- DIRECTION, TEACHER, OBSERVER, ADMIN_TECH
    totp_secret VARCHAR(100),               -- Secret 2FA TOTP (optionnel)
    is_2fa_enabled BOOLEAN DEFAULT FALSE,
    failed_attempts INT DEFAULT 0,
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);


-- ----------------------------------------------------------------------------
-- TABLE: trips - Voyages scolaires
-- ----------------------------------------------------------------------------
CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    destination VARCHAR(255) NOT NULL,      -- Ex: "Paris - Musée du Louvre"
    date DATE NOT NULL,
    description TEXT,
    created_by UUID REFERENCES users(id),   -- Direction qui a créé le voyage
    status VARCHAR(20) DEFAULT 'PLANNED',   -- PLANNED, ACTIVE, COMPLETED, ARCHIVED
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Note v4.1: Champ 'num_checkpoints' SUPPRIMÉ (calculé dynamiquement)

CREATE INDEX idx_trips_date ON trips(date);
CREATE INDEX idx_trips_status ON trips(status);


-- ----------------------------------------------------------------------------
-- TABLE: tokens - Stock de supports physiques (bracelets NFC)
-- ----------------------------------------------------------------------------
CREATE TABLE tokens (
    id SERIAL PRIMARY KEY,
    token_uid VARCHAR(50) UNIQUE NOT NULL,  -- Ex: "ST-001", "ST-042"
    token_type VARCHAR(20) NOT NULL,        -- NFC_PHYSICAL, QR_PHYSICAL
    status VARCHAR(20) DEFAULT 'AVAILABLE', -- AVAILABLE, ASSIGNED, DAMAGED, LOST
    created_at TIMESTAMP DEFAULT NOW(),
    last_assigned_at TIMESTAMP              -- Dernière assignation
);

CREATE INDEX idx_tokens_status ON tokens(status);
CREATE INDEX idx_tokens_uid ON tokens(token_uid);


-- ----------------------------------------------------------------------------
-- TABLE: assignments - Liaison dynamique token ↔ élève ↔ voyage
-- ----------------------------------------------------------------------------
CREATE TABLE assignments (
    id SERIAL PRIMARY KEY,
    token_uid VARCHAR(50) NOT NULL,         -- UID physique OU digital
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    assignment_type VARCHAR(20) NOT NULL,   -- NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL
    assigned_at TIMESTAMP DEFAULT NOW(),
    assigned_by UUID REFERENCES users(id),  -- Qui a fait l'assignation
    released_at TIMESTAMP,                  -- NULL = encore actif
    created_at TIMESTAMP DEFAULT NOW()
    -- Note: unicité gérée par index partiels (WHERE released_at IS NULL) ci-dessous
    -- pour permettre l'historique des réassignations sans violation de contrainte
);

CREATE INDEX idx_assignments_trip ON assignments(trip_id);
CREATE INDEX idx_assignments_student ON assignments(student_id);
CREATE INDEX idx_assignments_token ON assignments(token_uid);

-- ⭐ v4.2: Empêcher 2 assignations actives simultanées pour même token+voyage
CREATE UNIQUE INDEX idx_assignments_active_token_trip
ON assignments(token_uid, trip_id)
WHERE released_at IS NULL;

-- ⭐ v4.2: Empêcher 2 assignations actives simultanées pour même élève+voyage
CREATE UNIQUE INDEX idx_assignments_active_student_trip
ON assignments(student_id, trip_id)
WHERE released_at IS NULL;

COMMENT ON COLUMN assignments.token_uid IS
'UID physique (ex: ST-001) pour NFC/QR physique OU hash généré (ex: QR-a3f2c8) pour QR digital envoyé par email';


-- ----------------------------------------------------------------------------
-- TABLE: trip_students - Association voyage ↔ élèves participants
-- ----------------------------------------------------------------------------
CREATE TABLE trip_students (
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    added_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (trip_id, student_id)
);

CREATE INDEX idx_trip_students_trip ON trip_students(trip_id);
CREATE INDEX idx_trip_students_student ON trip_students(student_id);


-- ----------------------------------------------------------------------------
-- TABLE: checkpoints - Points de contrôle créés dynamiquement sur le terrain
-- ----------------------------------------------------------------------------
-- ARCHITECTURE v4.1: Checkpoints créés dynamiquement par les enseignants
-- ----------------------------------------------------------------------------
CREATE TABLE checkpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,             -- Ex: "Visite Musée du Louvre"
    description TEXT,
    sequence_order INT NOT NULL,            -- Ordre chronologique (auto-calculé)
    estimated_time TIME,                    -- Heure estimée (optionnel)

    created_by UUID REFERENCES users(id),   -- Quel prof a créé ce checkpoint
    created_at TIMESTAMP DEFAULT NOW(),

    started_at TIMESTAMP,                   -- Premier scan effectué
    closed_at TIMESTAMP,                    -- Checkpoint terminé (NULL = actif)
    status VARCHAR(20) DEFAULT 'DRAFT',     -- DRAFT, ACTIVE, CLOSED, ARCHIVED

    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_checkpoints_trip_sequence ON checkpoints(trip_id, sequence_order);
CREATE INDEX idx_checkpoints_trip ON checkpoints(trip_id);
CREATE INDEX idx_checkpoints_status ON checkpoints(status);

-- ⭐ v4.2: Index composite pour requêtes fréquentes
CREATE INDEX idx_checkpoints_trip_status ON checkpoints(trip_id, status);


-- ----------------------------------------------------------------------------
-- TABLE: checkpoint_participants - Élèves attendus à un checkpoint
-- ----------------------------------------------------------------------------
CREATE TABLE checkpoint_participants (
    checkpoint_id UUID REFERENCES checkpoints(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    added_at TIMESTAMP DEFAULT NOW(),
    added_by UUID REFERENCES users(id),
    PRIMARY KEY (checkpoint_id, student_id)
);

CREATE INDEX idx_checkpoint_participants_checkpoint ON checkpoint_participants(checkpoint_id);
CREATE INDEX idx_checkpoint_participants_student ON checkpoint_participants(student_id);


-- ----------------------------------------------------------------------------
-- TABLE: checkpoint_audit_log - Historique des modifications de checkpoints
-- ----------------------------------------------------------------------------
CREATE TABLE checkpoint_audit_log (
    id SERIAL PRIMARY KEY,
    checkpoint_id UUID REFERENCES checkpoints(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,            -- CREATED, STUDENT_ADDED, STUDENT_REMOVED, CLOSED, MODIFIED
    performed_by UUID REFERENCES users(id),
    details JSONB,
    performed_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_checkpoint_audit_checkpoint ON checkpoint_audit_log(checkpoint_id);
CREATE INDEX idx_checkpoint_audit_time ON checkpoint_audit_log(performed_at);


-- ----------------------------------------------------------------------------
-- TABLE: attendances - Présences scannées (avec support scans multiples)
-- Mode offline-first : client_uuid généré côté Flutter pour idempotence
-- ----------------------------------------------------------------------------
CREATE TABLE attendances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid UUID UNIQUE,                -- ⭐ Clé d'idempotence générée côté client (Flutter)
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    checkpoint_id UUID REFERENCES checkpoints(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    assignment_id INT REFERENCES assignments(id),

    scanned_at TIMESTAMP NOT NULL,          -- Timestamp local du client (offline-first)
    scanned_by UUID REFERENCES users(id),
    scan_method VARCHAR(20),                -- NFC, QR_PHYSICAL, QR_DIGITAL, MANUAL
    scan_sequence INT DEFAULT 1,            -- v4.1: 1er scan, 2e scan, 3e scan...

    is_manual BOOLEAN DEFAULT FALSE,
    justification VARCHAR(50),              -- Si manual: "Badge perdu", "Absent justifié"...
    comment TEXT,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Éviter les doublons de scan exact (même élève, même checkpoint, même seconde)
CREATE UNIQUE INDEX idx_attendances_unique_scan ON attendances(checkpoint_id, student_id, scanned_at);
-- Index sur client_uuid pour la vérification d'idempotence (déjà couvert par UNIQUE mais explicite)
CREATE INDEX idx_attendances_client_uuid ON attendances(client_uuid);
CREATE INDEX idx_attendances_trip ON attendances(trip_id);
CREATE INDEX idx_attendances_checkpoint ON attendances(checkpoint_id);
CREATE INDEX idx_attendances_student ON attendances(student_id);
CREATE INDEX idx_attendances_time ON attendances(scanned_at);

-- ⭐ v4.2: Index composite pour vérification présence rapide
CREATE INDEX idx_attendances_checkpoint_student ON attendances(checkpoint_id, student_id);


-- ----------------------------------------------------------------------------
-- TABLE: classes - Classes de l'école
-- ----------------------------------------------------------------------------
CREATE TABLE classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,      -- Ex: "6ème A", "TI-2024-BAC3"
    year VARCHAR(20),                       -- Ex: "2025-2026"
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);


-- ----------------------------------------------------------------------------
-- TABLE: class_teachers - Association classes ↔ enseignants responsables
-- ----------------------------------------------------------------------------
CREATE TABLE class_teachers (
    class_id UUID REFERENCES classes(id) ON DELETE CASCADE,
    teacher_id UUID REFERENCES users(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (class_id, teacher_id)
);


-- ----------------------------------------------------------------------------
-- TABLE: class_students - Association classes ↔ élèves (3FN)
-- ----------------------------------------------------------------------------
CREATE TABLE class_students (
    class_id UUID REFERENCES classes(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    enrolled_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (class_id, student_id)
);


-- ----------------------------------------------------------------------------
-- TABLE: alerts - Système d'alertes temps réel
-- ----------------------------------------------------------------------------
CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    checkpoint_id UUID REFERENCES checkpoints(id),
    student_id UUID NOT NULL REFERENCES students(id),  -- ⭐ v4.2: NOT NULL
    alert_type VARCHAR(50) NOT NULL,        -- STUDENT_MISSING, CHECKPOINT_DELAYED, SYNC_FAILED
    severity VARCHAR(20) DEFAULT 'MEDIUM',  -- LOW, MEDIUM, HIGH, CRITICAL
    message TEXT,
    status VARCHAR(20) DEFAULT 'ACTIVE',    -- ACTIVE, IN_PROGRESS, RESOLVED
    created_by UUID REFERENCES users(id),
    resolved_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE INDEX idx_alerts_trip ON alerts(trip_id);
CREATE INDEX idx_alerts_status ON alerts(status);
CREATE INDEX idx_alerts_severity ON alerts(severity);


-- ----------------------------------------------------------------------------
-- TABLE: sync_logs - Logs de synchronisation offline → online
-- ----------------------------------------------------------------------------
CREATE TABLE sync_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    trip_id UUID REFERENCES trips(id),
    device_id VARCHAR(255),
    records_synced INT,
    conflicts_detected INT DEFAULT 0,
    status VARCHAR(20),                     -- SUCCESS, PARTIAL_FAILURE, FAILED
    error_details JSONB,
    synced_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_sync_logs_user ON sync_logs(user_id);
CREATE INDEX idx_sync_logs_trip ON sync_logs(trip_id);
CREATE INDEX idx_sync_logs_time ON sync_logs(synced_at);


-- ----------------------------------------------------------------------------
-- TABLE: audit_logs - Logs d'audit globaux (sécurité RGPD)
-- ----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,           -- LOGIN, EXPORT_DATA, MODIFY_STUDENT...
    resource_type VARCHAR(50),              -- STUDENT, TRIP, CHECKPOINT, USER...
    resource_id UUID,
    ip_address INET,
    user_agent TEXT,
    details JSONB,
    performed_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_time ON audit_logs(performed_at);


-- ============================================================================
-- FONCTIONS ET TRIGGERS
-- ============================================================================

-- Mettre à jour automatiquement updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_students_updated_at BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_checkpoints_updated_at BEFORE UPDATE ON checkpoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_classes_updated_at BEFORE UPDATE ON classes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- Calculer automatiquement sequence_order pour les checkpoints
CREATE OR REPLACE FUNCTION set_checkpoint_sequence_order()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.sequence_order IS NULL THEN
        SELECT COALESCE(MAX(sequence_order), 0) + 1
        INTO NEW.sequence_order
        FROM checkpoints
        WHERE trip_id = NEW.trip_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_set_checkpoint_sequence BEFORE INSERT ON checkpoints
    FOR EACH ROW EXECUTE FUNCTION set_checkpoint_sequence_order();


-- Logger automatiquement les modifications de checkpoints
CREATE OR REPLACE FUNCTION log_checkpoint_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO checkpoint_audit_log (checkpoint_id, action, performed_by, details)
        VALUES (NEW.id, 'CREATED', NEW.created_by,
                jsonb_build_object('name', NEW.name));
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status <> NEW.status THEN
            INSERT INTO checkpoint_audit_log (checkpoint_id, action, performed_by, details)
            VALUES (NEW.id, 'STATUS_CHANGED', NEW.created_by,
                    jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status));
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER log_checkpoint_modifications AFTER INSERT OR UPDATE ON checkpoints
    FOR EACH ROW EXECUTE FUNCTION log_checkpoint_changes();


-- ============================================================================
-- VUES UTILITAIRES
-- ============================================================================

CREATE OR REPLACE VIEW v_trip_summary AS
SELECT
    t.id AS trip_id,
    t.destination,
    t.date,
    t.status,
    COUNT(DISTINCT ts.student_id) AS total_students,
    COUNT(DISTINCT c.id) AS total_checkpoints,
    COUNT(DISTINCT CASE WHEN c.status = 'CLOSED' THEN c.id END) AS closed_checkpoints,
    MAX(c.created_at) AS last_checkpoint_created
FROM trips t
LEFT JOIN trip_students ts ON t.id = ts.trip_id
LEFT JOIN checkpoints c ON t.id = c.trip_id
GROUP BY t.id;


CREATE OR REPLACE VIEW v_checkpoint_attendance_rate AS
SELECT
    c.id AS checkpoint_id,
    c.trip_id,
    c.name AS checkpoint_name,
    c.status,
    COUNT(DISTINCT cp.student_id) AS expected_students,
    COUNT(DISTINCT a.student_id) AS present_students,
    ROUND(
        CASE
            WHEN COUNT(DISTINCT cp.student_id) > 0
            THEN (COUNT(DISTINCT a.student_id)::DECIMAL / COUNT(DISTINCT cp.student_id)) * 100
            ELSE 0
        END, 2
    ) AS attendance_rate_percent
FROM checkpoints c
LEFT JOIN checkpoint_participants cp ON c.id = cp.checkpoint_id
LEFT JOIN attendances a ON c.id = a.checkpoint_id
GROUP BY c.id;


-- ============================================================================
-- DONNÉES DE TEST (dev uniquement)
-- ============================================================================

-- Utilisateur direction de test (mot de passe réel sera défini via l'API)
INSERT INTO users (email, password_hash, first_name, last_name, role, is_2fa_enabled)
VALUES ('admin@schooltrack.test', '$2b$12$dummyhashfortest', 'Admin', 'Test', 'DIRECTION', FALSE);

-- Enseignant de test
INSERT INTO users (email, password_hash, first_name, last_name, role, is_2fa_enabled)
VALUES ('teacher@schooltrack.test', '$2b$12$dummyhashfortest', 'Jean', 'Dupont', 'TEACHER', FALSE);

-- ============================================================================
-- FIN DU SCHÉMA v4.2
-- ============================================================================
