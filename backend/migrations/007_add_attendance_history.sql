-- Migration 007 : Historique brut des scans (US 3.2 — Fusion multi-enseignants)
--
-- attendance_history : archive TOUS les scans reçus via sync, même si supersédés.
-- attendances        : table canonique — 1 ligne par (student, checkpoint, trip).
--
-- Stratégie de fusion :
--   ACCEPTED      : premier scan pour ce (student, checkpoint) → inséré en canonique
--   MERGED_OLDEST : scan plus ancien qu'un canonique existant → a remplacé le canonique
--   SUPERSEDED    : scan plus récent → canonique existant (plus ancien) conservé

CREATE TABLE IF NOT EXISTS attendance_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid     UUID NOT NULL UNIQUE,

    trip_id         UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    checkpoint_id   UUID NOT NULL REFERENCES checkpoints(id) ON DELETE CASCADE,
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,

    scanned_at      TIMESTAMP NOT NULL,
    scanned_by      UUID REFERENCES users(id),
    scan_method     VARCHAR(20) NOT NULL,
    scan_sequence   INTEGER NOT NULL DEFAULT 1,
    is_manual       BOOLEAN NOT NULL DEFAULT FALSE,
    justification   VARCHAR(50),
    comment         TEXT,

    device_id       VARCHAR(255),
    sync_session_id UUID NOT NULL,
    synced_at       TIMESTAMP NOT NULL DEFAULT NOW(),

    -- ACCEPTED : scan inséré comme canonique (premier pour ce student+checkpoint)
    -- MERGED_OLDEST : ce scan était plus ancien → a remplacé le canonique
    -- SUPERSEDED : ce scan était plus récent → canonique existant conservé
    merge_status    VARCHAR(20) NOT NULL DEFAULT 'ACCEPTED'
);

CREATE INDEX IF NOT EXISTS idx_att_history_student_trip
    ON attendance_history(student_id, trip_id);

CREATE INDEX IF NOT EXISTS idx_att_history_sync_session
    ON attendance_history(sync_session_id);

-- Contrainte unique sur la table canonique : 1 seul scan par (student, checkpoint, trip).
-- On déduplication d'abord les éventuels doublons existants (garde le plus ancien).
DELETE FROM attendances
WHERE id NOT IN (
    SELECT DISTINCT ON (student_id, checkpoint_id, trip_id) id
    FROM attendances
    ORDER BY student_id, checkpoint_id, trip_id, scanned_at ASC, id ASC
);

ALTER TABLE attendances
    ADD CONSTRAINT IF NOT EXISTS uq_attendance_canonical
    UNIQUE (student_id, checkpoint_id, trip_id);
