-- Migration 003 : Mise a jour des mots de passe seed avec de vrais hash bcrypt (US 6.1)
-- admin@schooltrack.test → Admin123!
-- teacher@schooltrack.test → Teacher123!

UPDATE users SET password_hash = '$2b$12$kGMMYlNs9/Z5wnajznpNgeq/3wNVRl7fjAsGKps/s9rPQbWtnj9s.'
WHERE email = 'admin@schooltrack.test';

UPDATE users SET password_hash = '$2b$12$R3S3eEArQzvvfTyvw5ETK.nAfedJE3S93aEBccr4G3DHNUA4A6/6u'
WHERE email = 'teacher@schooltrack.test';
