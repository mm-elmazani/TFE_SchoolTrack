-- Migration 009 : Ajout methode 2FA (APP/EMAIL) + champs OTP email
-- Permet le choix entre 2FA par application TOTP ou par code envoye par email

ALTER TABLE users ADD COLUMN IF NOT EXISTS two_fa_method VARCHAR(10) DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_otp_code VARCHAR(10) DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_otp_expires TIMESTAMP DEFAULT NULL;

-- Mettre a jour les utilisateurs qui ont deja la 2FA activee (methode APP par defaut)
UPDATE users SET two_fa_method = 'APP' WHERE is_2fa_enabled = TRUE AND two_fa_method IS NULL;
