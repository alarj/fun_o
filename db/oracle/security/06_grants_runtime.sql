-- 06_grants_runtime.sql
-- Run as FUNO_APP after package creation.

grant execute on pkg_auth to FUNO_API;
grant execute on pkg_competitions to FUNO_API;
grant execute on pkg_questions to FUNO_API;
grant execute on pkg_submissions to FUNO_API;
grant execute on pkg_results to FUNO_API;

-- Optional: if API schema should call short names, run these under FUNO_API:
-- create synonym pkg_auth for FUNO_APP.pkg_auth;
-- create synonym pkg_competitions for FUNO_APP.pkg_competitions;
-- create synonym pkg_questions for FUNO_APP.pkg_questions;
-- create synonym pkg_submissions for FUNO_APP.pkg_submissions;
-- create synonym pkg_results for FUNO_APP.pkg_results;
