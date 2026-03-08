-- US 6.5 — Suppression logique des eleves (RGPD droit a l'effacement)
-- Ajoute is_deleted, deleted_at, deleted_by a la table students.
-- Les eleves supprimes logiquement sont conserves pour l'historique
-- mais exclus des requetes standard.

ALTER TABLE students ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE students ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;
ALTER TABLE students ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id);

-- Index partiel pour accelerer les requetes sur les eleves actifs
CREATE INDEX IF NOT EXISTS idx_students_active ON students(is_deleted) WHERE is_deleted = FALSE;
