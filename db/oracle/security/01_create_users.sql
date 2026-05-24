-- 01_create_users.sql
-- Creates application and API schemas for ORDS-based architecture.
-- Run as ADMIN (or privileged DBA user).

-- TODO: replace strong passwords before running.
-- Oracle Autonomous may require quoted usernames/password policies based on setup.

CREATE USER FUNO_APP IDENTIFIED BY "ChangeMe_App_#2026";
GRANT CREATE SESSION TO FUNO_APP;
GRANT CREATE TABLE TO FUNO_APP;
GRANT CREATE VIEW TO FUNO_APP;
GRANT CREATE SEQUENCE TO FUNO_APP;
GRANT CREATE PROCEDURE TO FUNO_APP;
GRANT CREATE TRIGGER TO FUNO_APP;
GRANT UNLIMITED TABLESPACE TO FUNO_APP;

CREATE USER FUNO_API IDENTIFIED BY "ChangeMe_Api_#2026";
GRANT CREATE SESSION TO FUNO_API;
GRANT CREATE PROCEDURE TO FUNO_API;

-- Optional: if you keep ORDS modules in API schema
GRANT CREATE TABLE TO FUNO_API;
GRANT CREATE VIEW TO FUNO_API;

-- Optional hardening baseline (adjust as needed)
ALTER USER FUNO_APP ACCOUNT UNLOCK;
ALTER USER FUNO_API ACCOUNT UNLOCK;
