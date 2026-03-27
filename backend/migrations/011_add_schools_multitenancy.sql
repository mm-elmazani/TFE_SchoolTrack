-- ============================================================================
-- MIGRATION 011 — Multi-tenancy par école (US 6.6)
-- ============================================================================
-- Ajoute la table schools et lie chaque entité parente (users, classes,
-- students, trips) à une école via school_id (row-level multi-tenancy).
-- ============================================================================

-- 1. Créer la table schools
CREATE TABLE IF NOT EXISTS schools (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(255) NOT NULL,
    slug       VARCHAR(100) UNIQUE NOT NULL,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. Insérer les 2 schools seed
INSERT INTO schools (name, slug)
VALUES
    ('École de développement', 'dev'),
    ('École client',           'client')
ON CONFLICT (slug) DO NOTHING;

-- 3. Ajouter school_id (nullable d'abord) sur les 4 tables parentes
ALTER TABLE users    ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE classes  ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE students ADD COLUMN IF NOT EXISTS school_id UUID;
ALTER TABLE trips    ADD COLUMN IF NOT EXISTS school_id UUID;

-- 4. Lier toutes les données existantes à l'école "dev"
UPDATE users    SET school_id = (SELECT id FROM schools WHERE slug = 'dev') WHERE school_id IS NULL;
UPDATE classes  SET school_id = (SELECT id FROM schools WHERE slug = 'dev') WHERE school_id IS NULL;
UPDATE students SET school_id = (SELECT id FROM schools WHERE slug = 'dev') WHERE school_id IS NULL;
UPDATE trips    SET school_id = (SELECT id FROM schools WHERE slug = 'dev') WHERE school_id IS NULL;

-- 5. Passer NOT NULL après le backfill
ALTER TABLE users    ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE classes  ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE students ALTER COLUMN school_id SET NOT NULL;
ALTER TABLE trips    ALTER COLUMN school_id SET NOT NULL;

-- 6. Ajouter les FK vers schools
ALTER TABLE users    ADD CONSTRAINT fk_users_school    FOREIGN KEY (school_id) REFERENCES schools(id);
ALTER TABLE classes  ADD CONSTRAINT fk_classes_school  FOREIGN KEY (school_id) REFERENCES schools(id);
ALTER TABLE students ADD CONSTRAINT fk_students_school FOREIGN KEY (school_id) REFERENCES schools(id);
ALTER TABLE trips    ADD CONSTRAINT fk_trips_school    FOREIGN KEY (school_id) REFERENCES schools(id);

-- 7. Contrainte d'unicité du nom de classe par école
--    (remplace l'ancienne contrainte globale sur name)
ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_name_key;
ALTER TABLE classes ADD CONSTRAINT uq_classes_name_school UNIQUE (name, school_id);

-- 8. Index de performance
CREATE INDEX IF NOT EXISTS idx_users_school    ON users(school_id);
CREATE INDEX IF NOT EXISTS idx_classes_school  ON classes(school_id);
CREATE INDEX IF NOT EXISTS idx_students_school ON students(school_id);
CREATE INDEX IF NOT EXISTS idx_trips_school    ON trips(school_id);
