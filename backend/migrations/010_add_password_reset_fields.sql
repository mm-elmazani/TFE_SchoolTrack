-- Migration 010 : Ajout des champs pour le reset de mot de passe (US 6.1)
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_expires TIMESTAMP;
