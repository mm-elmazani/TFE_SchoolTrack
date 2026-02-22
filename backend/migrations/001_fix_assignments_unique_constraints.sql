-- ============================================================================
-- MIGRATION 001 — Correction des contraintes UNIQUE sur assignments
-- ============================================================================
-- Problème : les contraintes UNIQUE ordinaires (student_id, trip_id) et
--            (token_uid, trip_id) bloquent les réassignations car elles
--            s'appliquent à TOUTES les lignes, même celles avec released_at rempli.
-- Solution  : supprimer ces contraintes, les index partiels WHERE released_at IS NULL
--             suffisent pour garantir l'unicité des assignations ACTIVES.
-- ============================================================================

BEGIN;

-- Supprimer la contrainte ordinaire sur (student_id, trip_id)
ALTER TABLE assignments
    DROP CONSTRAINT IF EXISTS assignments_student_id_trip_id_key;

-- Supprimer la contrainte ordinaire sur (token_uid, trip_id)
ALTER TABLE assignments
    DROP CONSTRAINT IF EXISTS assignments_token_uid_trip_id_key;

-- Ajouter l'index partiel pour token actif (token_uid + trip_id)
-- (l'index pour student_id + trip_id est déjà créé dans init.sql v4.2)
CREATE UNIQUE INDEX IF NOT EXISTS idx_assignments_active_token_trip
    ON assignments(token_uid, trip_id)
    WHERE released_at IS NULL;

COMMIT;
