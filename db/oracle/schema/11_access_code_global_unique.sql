-- 11_access_code_global_unique.sql
-- Run as FUNO_APP
-- Ensures access code is globally unique across full history.

create unique index ux_competition_access_code_global on competition_access_codes (code);

commit;
