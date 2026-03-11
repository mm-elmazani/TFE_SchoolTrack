-- Migration US 1.4 : Ajout du champ hardware_uid a la table tokens
-- UID hardware NFC (hex) lu lors de l'encodage du bracelet

ALTER TABLE tokens ADD COLUMN IF NOT EXISTS hardware_uid VARCHAR(100);
