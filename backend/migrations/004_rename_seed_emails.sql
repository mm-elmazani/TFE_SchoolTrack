-- Migration 004 : Renommer les emails seed .test → .be (Pydantic rejette le TLD .test)

UPDATE users SET email = 'admin@schooltrack.be' WHERE email = 'admin@schooltrack.test';
UPDATE users SET email = 'teacher@schooltrack.be' WHERE email = 'teacher@schooltrack.test';
