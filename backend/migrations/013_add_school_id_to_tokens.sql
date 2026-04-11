-- Migration 013 : Isolation multi-tenant des tokens (bracelets)
-- La table tokens n'avait pas de colonne school_id, rendant les bracelets
-- visibles par toutes les écoles. Cette migration corrige ce manque.
--
-- IMPORTANT (prod) : après application, les tokens existants auront school_id = NULL.
-- Ils seront invisibles pour toutes les écoles. Les admins devront re-créer
-- leurs tokens depuis le dashboard ou les réassigner via SQL :
--   UPDATE tokens SET school_id = '<uuid-école>' WHERE school_id IS NULL;

ALTER TABLE tokens
    ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES schools(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tokens_school_id ON tokens(school_id);
