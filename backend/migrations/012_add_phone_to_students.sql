-- Migration 012 : ajout du champ phone aux élèves
-- phone est chiffré AES-256-GCM côté applicatif (EncryptedString), stocké en TEXT
ALTER TABLE students ADD COLUMN IF NOT EXISTS phone TEXT;
