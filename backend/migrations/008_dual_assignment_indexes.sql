-- Migration 008: Permettre double assignation (physique + QR digital) par eleve par voyage
-- Remplace l'index unique global par 2 index par categorie

-- Supprimer l'ancien index qui bloquait toute double assignation
DROP INDEX IF EXISTS idx_assignments_active_student_trip;

-- Max 1 assignation physique active par eleve+voyage (NFC_PHYSICAL ou QR_PHYSICAL)
CREATE UNIQUE INDEX idx_assignments_active_student_trip_physical
ON assignments(student_id, trip_id)
WHERE released_at IS NULL AND assignment_type != 'QR_DIGITAL';

-- Max 1 assignation digitale active par eleve+voyage (QR_DIGITAL)
CREATE UNIQUE INDEX idx_assignments_active_student_trip_digital
ON assignments(student_id, trip_id)
WHERE released_at IS NULL AND assignment_type = 'QR_DIGITAL';
