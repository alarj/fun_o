-- 03_ords_enable_and_security.sql (Autonomous-safe)
-- Purpose: enable REST for FUNO_API schema and set up ORDS roles/privileges when supported.
-- Run as ADMIN in Autonomous Database (SQL Worksheet / SQLcl).

set serveroutput on;

declare
  v_err varchar2(4000);
begin
  -- Attempt ORDS_ADMIN.ENABLE_SCHEMA (preferred in Autonomous).
  begin
    ORDS_ADMIN.ENABLE_SCHEMA(
      p_enabled             => true,
      p_schema              => 'FUNO_API',
      p_url_mapping_type    => 'BASE_PATH',
      p_url_mapping_pattern => 'funo',
      p_auto_rest_auth      => true
    );
    dbms_output.put_line('OK: ORDS_ADMIN.ENABLE_SCHEMA executed for FUNO_API.');
  exception
    when others then
      v_err := sqlerrm;
      dbms_output.put_line('WARN: ORDS_ADMIN.ENABLE_SCHEMA failed: ' || v_err);

      -- Fallback attempt for environments exposing ORDS.ENABLE_SCHEMA.
      begin
        ORDS.ENABLE_SCHEMA(
          p_enabled             => true,
          p_schema              => 'FUNO_API',
          p_url_mapping_type    => 'BASE_PATH',
          p_url_mapping_pattern => 'funo',
          p_auto_rest_auth      => true
        );
        dbms_output.put_line('OK: ORDS.ENABLE_SCHEMA fallback executed for FUNO_API.');
      exception
        when others then
          dbms_output.put_line('ERROR: Fallback ORDS.ENABLE_SCHEMA failed: ' || sqlerrm);
          raise;
      end;
  end;

  commit;
end;
/

-- Role + privilege setup.
-- In some Autonomous setups, these procedures are available under ORDS,
-- in others they may be restricted. Script logs status.
declare
  procedure try_exec(p_sql varchar2) is
  begin
    execute immediate p_sql;
    dbms_output.put_line('OK: ' || p_sql);
  exception
    when others then
      dbms_output.put_line('WARN: failed -> ' || p_sql || ' | ' || sqlerrm);
  end;
begin
  -- Create roles (idempotent-like behavior via exception logging).
  try_exec(q'[begin ORDS.CREATE_ROLE(p_role_name => 'funo.competitor'); end;]');
  try_exec(q'[begin ORDS.CREATE_ROLE(p_role_name => 'funo.organizer'); end;]');
  try_exec(q'[begin ORDS.CREATE_ROLE(p_role_name => 'funo.system_owner'); end;]');

  -- Define privileges and URL pattern bindings.
  try_exec(q'[begin ORDS.DEFINE_PRIVILEGE(
    p_privilege_name => 'priv.competitor',
    p_roles          => OWA.VC_ARR('funo.competitor'),
    p_patterns       => OWA.VC_ARR('/competitor/*'),
    p_label          => 'Competitor API access',
    p_description    => 'Access for competitor endpoints.'
  ); end;]');

  try_exec(q'[begin ORDS.DEFINE_PRIVILEGE(
    p_privilege_name => 'priv.organizer',
    p_roles          => OWA.VC_ARR('funo.organizer'),
    p_patterns       => OWA.VC_ARR('/organizer/*'),
    p_label          => 'Organizer API access',
    p_description    => 'Access for organizer endpoints.'
  ); end;]');

  try_exec(q'[begin ORDS.DEFINE_PRIVILEGE(
    p_privilege_name => 'priv.system_owner',
    p_roles          => OWA.VC_ARR('funo.system_owner'),
    p_patterns       => OWA.VC_ARR('/owner/*'),
    p_label          => 'System owner API access',
    p_description    => 'Access for system owner endpoints.'
  ); end;]');

  commit;
end;
/

-- Notes:
-- 1) If CREATE_ROLE / DEFINE_PRIVILEGE are restricted in your tenant, manage them in ORDS UI/Database Actions.
-- 2) Keep FUNO_API as REST facade; do not expose FUNO_APP base tables directly.
