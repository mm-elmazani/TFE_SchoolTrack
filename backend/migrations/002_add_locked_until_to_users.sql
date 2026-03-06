-- Migration 002 : Ajout du champ locked_until pour le verrouillage de compte (US 6.1)
-- A appliquer sur la base PostgreSQL existante

ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;
