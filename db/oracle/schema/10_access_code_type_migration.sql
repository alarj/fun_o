-- 10_access_code_type_migration.sql
-- Run as FUNO_APP (incremental migration)

alter table competition_access_codes add (code_type varchar2(20) default 'COMPETITOR' not null);
alter table competition_access_codes add constraint chk_cac_code_type check (code_type in ('COMPETITOR','ORGANIZER'));

commit;
