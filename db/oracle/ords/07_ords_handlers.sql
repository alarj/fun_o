-- 07_ords_handlers.sql
-- Run as FUNO_API (schema already enabled in ORDS)
-- Assumes grants from FUNO_APP to FUNO_API are in place.

begin
  ORDS.DEFINE_MODULE(
    p_module_name    => 'funo.api',
    p_base_path      => '/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED'
  );

  -- POST /funo/auth/google/upsert
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/google/upsert'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/google/upsert',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body      json_object_t;
        l_user_id   number;
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_auth.upsert_google_user(
          p_google_sub => l_body.get_string('google_sub'),
          p_email      => l_body.get_string('email'),
          p_full_name  => case when l_body.has('full_name') then l_body.get_string('full_name') else null end,
          o_user_id    => l_user_id
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('user_id' value l_user_id));
      end;
    ]'
  );

  -- GET /funo/auth/has-role?user_id=..&role_code=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/has-role'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/has-role',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_has_role varchar2(1);
      begin
        FUNO_APP.pkg_auth.has_active_role(
          p_user_id   => to_number(:user_id),
          p_role_code => :role_code,
          o_has_role  => l_has_role
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('has_role' value nvl(l_has_role, 'N')));
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'auth/has-role',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'auth/has-role',
    p_method             => 'GET',
    p_name               => 'role_code',
    p_bind_variable_name => 'role_code',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );

  -- GET /funo/auth/user-profile?user_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/user-profile'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/user-profile',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_email varchar2(320);
        l_full_name varchar2(200);
      begin
        FUNO_APP.pkg_auth.get_user_profile(
          p_user_id   => to_number(:user_id),
          o_email     => l_email,
          o_full_name => l_full_name
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('email' value l_email, 'full_name' value l_full_name));
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'auth/user-profile',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/admin/competition-overview?competition_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competition-overview');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competition-overview',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.get_competition_overview_json(
          p_competition_id => to_number(:competition_id),
          o_overview_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{}'));
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/competition-overview',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/superadmin/competitions
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'superadmin/competitions');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'superadmin/competitions',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.list_all_competitions_json(
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );

  -- POST /funo/superadmin/competitions
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'superadmin/competitions',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_competition_id number;
        l_organizer_code varchar2(20);
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.create_empty_competition(
          p_name => l_body.get_string('name'),
          p_description => case when l_body.has('description') then l_body.get_string('description') else null end,
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_competition_id => l_competition_id,
          o_organizer_code => l_organizer_code
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('competition_id' value l_competition_id, 'organizer_code' value l_organizer_code));
      end;
    ]'
  );

  -- POST /funo/superadmin/competitions/copy
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'superadmin/competitions/copy');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'superadmin/competitions/copy',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_competition_id number;
        l_organizer_code varchar2(20);
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.copy_competition(
          p_source_competition_id => l_body.get_number('source_competition_id'),
          p_copy_questions        => case when l_body.has('copy_questions') then l_body.get_string('copy_questions') else 'N' end,
          p_copy_organizers       => case when l_body.has('copy_organizers') then l_body.get_string('copy_organizers') else 'N' end,
          p_created_by            => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_competition_id        => l_competition_id,
          o_organizer_code        => l_organizer_code
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('competition_id' value l_competition_id, 'organizer_code' value l_organizer_code));
      end;
    ]'
  );

  -- POST /funo/superadmin/organizers/remove
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'superadmin/organizers/remove');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'superadmin/organizers/remove',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.remove_competition_organizer(
          p_competition_id => l_body.get_number('competition_id'),
          p_user_id        => l_body.get_number('user_id'),
          p_removed_by     => case when l_body.has('removed_by') then l_body.get_number('removed_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- GET /funo/admin/questions-overview?competition_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/questions-overview');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/questions-overview',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
        l_len pls_integer;
        l_pos pls_integer := 1;
        l_step pls_integer := 2000;
      begin
        FUNO_APP.pkg_admin_content.get_questions_overview_json(
          p_competition_id => to_number(:competition_id),
          o_questions_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.prn('{"items":');
        if l_json is null then
          htp.prn('[]');
        else
          l_len := dbms_lob.getlength(l_json);
          while l_pos <= l_len loop
            htp.prn(dbms_lob.substr(l_json, l_step, l_pos));
            l_pos := l_pos + l_step;
          end loop;
        end if;
        htp.prn('}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/questions-overview',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- POST /funo/admin/access-codes
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/access-codes');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/access-codes',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_access_code_id number;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.upsert_access_code(
          p_competition_id => l_body.get_number('competition_id'),
          p_code_type => l_body.get_string('code_type'),
          p_code => l_body.get_string('code'),
          p_status => case when l_body.has('status') then l_body.get_string('status') else 'ACTIVE' end,
          p_expires_at => null,
          p_max_uses => case when l_body.has('max_uses') then l_body.get_number('max_uses') else null end,
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_access_code_id => l_access_code_id
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('access_code_id' value l_access_code_id));
      end;
    ]'
  );

  -- GET /funo/admin/competitions
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competitions');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.list_competitions_json(
          p_user_id => to_number(:user_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/competitions',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/admin/checkpoints?competition_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/checkpoints');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/checkpoints',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.list_checkpoints_json(
          p_competition_id => to_number(:competition_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/checkpoints',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- POST /funo/auth/dev/resolve-user
  -- Dev helper for local testing without Google token.
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/dev/resolve-user'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'auth/dev/resolve-user',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body     json_object_t;
        l_user_id  number;
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_auth.resolve_user_for_dev(
          p_user_id => case when l_body.has('user_id') then l_body.get_number('user_id') else null end,
          p_email   => case when l_body.has('email') then l_body.get_string('email') else null end,
          o_user_id => l_user_id
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('user_id' value l_user_id));
      end;
    ]'
  );

  -- POST /funo/competitions/register
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'competitions/register'
  );

  -- POST /funo/organizers/register
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizers/register'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizers/register',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body            json_object_t;
        l_competition_id  number;
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_competitions.register_organizer_by_code(
          p_user_id        => l_body.get_number('user_id'),
          p_access_code    => l_body.get_string('access_code'),
          o_competition_id => l_competition_id
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('competition_id' value l_competition_id));
      end;
    ]'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitions/register',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body            json_object_t;
        l_competition_id  number;
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_competitions.register_to_competition(
          p_user_id        => l_body.get_number('user_id'),
          p_access_code    => l_body.get_string('access_code'),
          o_competition_id => l_competition_id
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('competition_id' value l_competition_id));
      end;
    ]'
  );

  -- POST /funo/submissions
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'submissions'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'submissions',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body           json_object_t;
        l_submission_id  number;
        l_is_correct     varchar2(1);
        l_awarded_points number;
        l_total_score    number;
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_submissions.submit_answer(
          p_user_id        => l_body.get_number('user_id'),
          p_competition_id => l_body.get_number('competition_id'),
          p_checkpoint_id  => l_body.get_number('checkpoint_id'),
          p_question_id    => l_body.get_number('question_id'),
          p_answer_text    => case when l_body.has('answer_text') then l_body.get_string('answer_text') else null end,
          p_selected_option_id => case when l_body.has('selected_option_id') then l_body.get_number('selected_option_id') else null end,
          p_latitude => case when l_body.has('latitude') then l_body.get_number('latitude') else null end,
          p_longitude => case when l_body.has('longitude') then l_body.get_number('longitude') else null end,
          p_radius_m => case when l_body.has('radius_m') then l_body.get_number('radius_m') else null end,
          o_submission_id  => l_submission_id,
          o_is_correct     => l_is_correct,
          o_awarded_points => l_awarded_points,
          o_total_score    => l_total_score
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(
          json_object(
            'submission_id' value l_submission_id,
            'is_correct' value l_is_correct,
            'awarded_points' value nvl(l_awarded_points, 0),
            'total_score' value nvl(l_total_score, 0)
          )
        );
      end;
    ]'
  );

  -- GET /funo/competitor/competitions?user_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/competitions');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/competitions',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.list_my_competitions_json(
          p_user_id => to_number(:user_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/competitions',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/session-by-participant?user_id=..&competition_participant_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/session-by-participant');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/session-by-participant',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.get_session_by_participant_json(
          p_user_id => to_number(:user_id),
          p_competition_participant_id => to_number(:competition_participant_id),
          o_item_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        if l_json is null then
          htp.p('{}');
        else
          htp.p('{"participant":' || l_json || '}');
        end if;
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/session-by-participant',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/session-by-participant',
    p_method             => 'GET',
    p_name               => 'competition_participant_id',
    p_bind_variable_name => 'competition_participant_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/terms?user_id=..&competition_id=..&lang_code=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/terms');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/terms',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.get_terms_for_competition_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          p_lang_code => :lang_code,
          o_item_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{}'));
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/terms',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/terms',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/terms',
    p_method             => 'GET',
    p_name               => 'lang_code',
    p_bind_variable_name => 'lang_code',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );

  -- POST /funo/competitor/join-preview
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/join-preview');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/join-preview',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_json clob;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_competitor.join_preview_json(
          p_user_id => case when l_body.has('user_id') then l_body.get_number('user_id') else null end,
          p_access_code => l_body.get_string('access_code'),
          p_lang_code => case when l_body.has('lang_code') then l_body.get_string('lang_code') else null end,
          p_alias_display => case when l_body.has('alias_display') then l_body.get_string('alias_display') else null end,
          o_item_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{}'));
      end;
    ]'
  );

  -- POST /funo/competitor/join-complete
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/join-complete');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/join-complete',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_user_id number;
        l_competition_id number;
        l_competition_participant_id number;
        l_switched_from_participant_id number;
        l_no_change varchar2(1);
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_competitor.join_by_code(
          p_user_id => case when l_body.has('user_id') then l_body.get_number('user_id') else null end,
          p_access_code => l_body.get_string('access_code'),
          p_alias_display => l_body.get_string('alias_display'),
          p_contact_email => case when l_body.has('contact_email') then l_body.get_string('contact_email') else null end,
          p_terms_id => l_body.get_number('terms_id'),
          p_terms_lang_code => l_body.get_string('terms_lang_code'),
          p_accept_terms => l_body.get_string('accept_terms'),
          p_current_competition_participant_id => case when l_body.has('current_competition_participant_id') then l_body.get_number('current_competition_participant_id') else null end,
          o_user_id => l_user_id,
          o_competition_id => l_competition_id,
          o_competition_participant_id => l_competition_participant_id,
          o_switched_from_participant_id => l_switched_from_participant_id,
          o_no_change => l_no_change
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(
          json_object(
            'user_id' value l_user_id,
            'competition_id' value l_competition_id,
            'competition_participant_id' value l_competition_participant_id,
            'switched_from_participant_id' value l_switched_from_participant_id,
            'no_change' value nvl(l_no_change, 'N')
          )
        );
      end;
    ]'
  );

  -- GET /funo/competitor/open-checkpoints?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/open-checkpoints');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/open-checkpoints',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.list_open_checkpoints_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          p_latitude => case when :latitude is not null then to_number(:latitude) else null end,
          p_longitude => case when :longitude is not null then to_number(:longitude) else null end,
          p_radius_m => case when :radius_m is not null then to_number(:radius_m) else null end,
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/open-checkpoints',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/open-checkpoints',
    p_method             => 'GET',
    p_name               => 'latitude',
    p_bind_variable_name => 'latitude',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/open-checkpoints',
    p_method             => 'GET',
    p_name               => 'longitude',
    p_bind_variable_name => 'longitude',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/open-checkpoints',
    p_method             => 'GET',
    p_name               => 'radius_m',
    p_bind_variable_name => 'radius_m',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/open-checkpoints',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/map-checkpoints?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/map-checkpoints');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/map-checkpoints',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.list_map_checkpoints_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/map-checkpoints',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/map-checkpoints',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/progress?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/progress');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/progress',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.get_progress_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          o_progress_json => l_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{"total_checkpoints":0,"answered_checkpoints":0,"score":0}'));
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/progress',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/progress',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/my-submissions?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/my-submissions');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/my-submissions',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.list_my_submissions_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/my-submissions',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/my-submissions',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/competitor/my-submission-detail?competition_id=..&user_id=..&submission_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'competitor/my-submission-detail');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'competitor/my-submission-detail',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_competitor.get_my_submission_detail_json(
          p_user_id => to_number(:user_id),
          p_competition_id => to_number(:competition_id),
          p_submission_id => to_number(:submission_id),
          o_item_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{}'));
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/my-submission-detail',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/my-submission-detail',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'competitor/my-submission-detail',
    p_method             => 'GET',
    p_name               => 'submission_id',
    p_bind_variable_name => 'submission_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/results/score?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'results/score'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'results/score',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
      declare
        l_score number;
      begin
        FUNO_APP.pkg_results.get_competition_score(
          p_competition_id => to_number(:competition_id),
          p_user_id        => to_number(:user_id),
          o_score          => l_score
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('score' value nvl(l_score, 0)));
      end;
    ]'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'results/score',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'results/score',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/organizer/leaderboard?competition_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/leaderboard'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/leaderboard',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_items_json clob;
      begin
        FUNO_APP.pkg_results.get_competition_leaderboard(
          p_competition_id => to_number(:competition_id),
          o_items_json     => l_items_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_items_json, '[]') || '}');
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/leaderboard',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/organizer/checkpoint-results?competition_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/checkpoint-results'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/checkpoint-results',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_items_json clob;
      begin
        FUNO_APP.pkg_results.get_checkpoint_results(
          p_competition_id => to_number(:competition_id),
          o_items_json     => l_items_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_items_json, '[]') || '}');
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/checkpoint-results',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/organizer/checkpoint-responders?competition_id=..&checkpoint_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/checkpoint-responders'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/checkpoint-responders',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_items_json clob;
      begin
        FUNO_APP.pkg_results.get_checkpoint_responders(
          p_competition_id => to_number(:competition_id),
          p_checkpoint_id  => to_number(:checkpoint_id),
          o_items_json     => l_items_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_items_json, '[]') || '}');
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/checkpoint-responders',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/checkpoint-responders',
    p_method             => 'GET',
    p_name               => 'checkpoint_id',
    p_bind_variable_name => 'checkpoint_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/organizer/participant-submissions?competition_id=..&user_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/participant-submissions'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/participant-submissions',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_items_json clob;
      begin
        FUNO_APP.pkg_results.get_participant_submissions(
          p_competition_id => to_number(:competition_id),
          p_user_id        => to_number(:user_id),
          o_items_json     => l_items_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_items_json, '[]') || '}');
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/participant-submissions',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/participant-submissions',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/organizer/submission-detail?competition_id=..&user_id=..&submission_id=..
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/submission-detail'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'organizer/submission-detail',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_item_json clob;
      begin
        FUNO_APP.pkg_results.get_submission_detail(
          p_competition_id => to_number(:competition_id),
          p_user_id        => to_number(:user_id),
          p_submission_id  => to_number(:submission_id),
          o_item_json      => l_item_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_item_json, '{}'));
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/submission-detail',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/submission-detail',
    p_method             => 'GET',
    p_name               => 'user_id',
    p_bind_variable_name => 'user_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'organizer/submission-detail',
    p_method             => 'GET',
    p_name               => 'submission_id',
    p_bind_variable_name => 'submission_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- GET /funo/i18n/translations?lang=et&default_lang=et
  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'funo.api',
    p_pattern     => 'i18n/translations'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'i18n/translations',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_lang varchar2(10) := nvl(:lang, 'et');
        l_default_lang varchar2(10) := nvl(:default_lang, 'et');
        l_items_json clob;
      begin
        FUNO_APP.pkg_i18n.get_translations_json(
          p_lang_code => l_lang,
          p_default_lang_code => l_default_lang,
          o_items_json => l_items_json
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"lang":"' || l_lang || '","default_lang":"' || l_default_lang || '","items":' || nvl(l_items_json, '{}') || '}');
      end;
    ~'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'i18n/translations',
    p_method             => 'GET',
    p_name               => 'lang',
    p_bind_variable_name => 'lang',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );

  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'i18n/translations',
    p_method             => 'GET',
    p_name               => 'default_lang',
    p_bind_variable_name => 'default_lang',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );

  -- POST /funo/admin/checkpoints
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/checkpoints');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/checkpoints',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_checkpoint_id number;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.create_checkpoint(
          p_competition_id => l_body.get_number('competition_id'),
          p_title => l_body.get_string('title'),
          p_order_no => case when l_body.has('order_no') then l_body.get_number('order_no') else null end,
          p_location_hint => case when l_body.has('location_hint') then l_body.get_string('location_hint') else null end,
          p_latitude => case when l_body.has('latitude') then l_body.get_number('latitude') else null end,
          p_longitude => case when l_body.has('longitude') then l_body.get_number('longitude') else null end,
          p_radius_m => case when l_body.has('radius_m') then l_body.get_number('radius_m') else null end,
          p_location_required => case when l_body.has('location_required') then l_body.get_string('location_required') else null end,
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_checkpoint_id => l_checkpoint_id
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('checkpoint_id' value l_checkpoint_id));
      end;
    ]'
  );

  -- POST /funo/admin/questions
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/questions');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/questions',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_question_id number;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.create_question(
          p_checkpoint_id => l_body.get_number('checkpoint_id'),
          p_question_type => l_body.get_string('question_type'),
          p_input_type => case when l_body.has('input_type') then l_body.get_string('input_type') else null end,
          p_input_max_length => case when l_body.has('input_max_length') then l_body.get_number('input_max_length') else null end,
          p_input_pattern => case when l_body.has('input_pattern') then l_body.get_string('input_pattern') else null end,
          p_points => case when l_body.has('points') then l_body.get_number('points') else 0 end,
          p_wrong_points => case when l_body.has('wrong_points') then l_body.get_number('wrong_points') else 0 end,
          p_lang_code => case when l_body.has('lang_code') then l_body.get_string('lang_code') else 'et' end,
          p_question_text => l_body.get_string('question_text'),
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_question_id => l_question_id
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('question_id' value l_question_id));
      end;
    ]'
  );

  -- POST /funo/admin/question-options
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/question-options');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/question-options',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_option_id number;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.create_question_option(
          p_question_id => l_body.get_number('question_id'),
          p_option_code => l_body.get_string('option_code'),
          p_order_no => l_body.get_number('order_no'),
          p_is_correct => case when l_body.has('is_correct') then l_body.get_string('is_correct') else 'N' end,
          p_lang_code => case when l_body.has('lang_code') then l_body.get_string('lang_code') else 'et' end,
          p_option_text => l_body.get_string('option_text'),
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_option_id => l_option_id
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('option_id' value l_option_id));
      end;
    ]'
  );

  -- POST /funo/admin/question-answers
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/question-answers');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/question-answers',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_answer_id number;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.create_question_answer(
          p_question_id => l_body.get_number('question_id'),
          p_answer_value => l_body.get_string('answer_value'),
          p_normalize_mode => case when l_body.has('normalize_mode') then l_body.get_string('normalize_mode') else 'EXACT' end,
          p_is_correct => case when l_body.has('is_correct') then l_body.get_string('is_correct') else 'Y' end,
          p_created_by => case when l_body.has('created_by') then l_body.get_number('created_by') else null end,
          o_answer_id => l_answer_id
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('answer_id' value l_answer_id));
      end;
    ]'
  );

  -- POST /funo/admin/checkpoints/update
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/checkpoints/update');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/checkpoints/update',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.update_checkpoint(
          p_checkpoint_id => l_body.get_number('checkpoint_id'),
          p_title => l_body.get_string('title'),
          p_order_no => case when l_body.has('order_no') then l_body.get_number('order_no') else null end,
          p_location_hint => case when l_body.has('location_hint') then l_body.get_string('location_hint') else null end,
          p_latitude => case when l_body.has('latitude') then l_body.get_number('latitude') else null end,
          p_longitude => case when l_body.has('longitude') then l_body.get_number('longitude') else null end,
          p_radius_m => case when l_body.has('radius_m') then l_body.get_number('radius_m') else null end,
          p_location_required => case when l_body.has('location_required') then l_body.get_string('location_required') else null end,
          p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- POST /funo/admin/checkpoints/delete
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/checkpoints/delete');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/checkpoints/delete',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.soft_delete_checkpoint(
          p_checkpoint_id => l_body.get_number('checkpoint_id'),
          p_deleted_by => case when l_body.has('deleted_by') then l_body.get_number('deleted_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- POST /funo/admin/questions/update
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/questions/update');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/questions/update',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.update_question(
          p_question_id => l_body.get_number('question_id'),
          p_checkpoint_id => l_body.get_number('checkpoint_id'),
          p_question_type => l_body.get_string('question_type'),
          p_input_type => case when l_body.has('input_type') then l_body.get_string('input_type') else null end,
          p_input_max_length => case when l_body.has('input_max_length') then l_body.get_number('input_max_length') else null end,
          p_input_pattern => case when l_body.has('input_pattern') then l_body.get_string('input_pattern') else null end,
          p_points => case when l_body.has('points') then l_body.get_number('points') else 0 end,
          p_wrong_points => case when l_body.has('wrong_points') then l_body.get_number('wrong_points') else 0 end,
          p_lang_code => case when l_body.has('lang_code') then l_body.get_string('lang_code') else 'et' end,
          p_question_text => l_body.get_string('question_text'),
          p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
        );

        if l_body.has('options_json') then
          FUNO_APP.pkg_admin_content.replace_question_options_et(
            p_question_id => l_body.get_number('question_id'),
            p_options_json => l_body.get_clob('options_json'),
            p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
          );
        end if;
        if l_body.has('answers_json') then
          FUNO_APP.pkg_admin_content.replace_question_answers(
            p_question_id => l_body.get_number('question_id'),
            p_answers_json => l_body.get_clob('answers_json'),
            p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
          );
        end if;

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- POST /funo/admin/questions/delete
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/questions/delete');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/questions/delete',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.soft_delete_question(
          p_question_id => l_body.get_number('question_id'),
          p_deleted_by => case when l_body.has('deleted_by') then l_body.get_number('deleted_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- POST /funo/admin/competitions/dates
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competitions/dates');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/dates',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'[
      declare
        l_body json_object_t;
        l_starts timestamp;
        l_ends timestamp;
        l_starts_raw varchar2(100);
        l_ends_raw varchar2(100);
      begin
        l_body := json_object_t.parse(:body_text);
        l_starts_raw := case
          when l_body.has('starts_at') and l_body.get('starts_at') is not null and not l_body.get('starts_at').is_null then l_body.get_string('starts_at')
          else null
        end;
        l_ends_raw := case
          when l_body.has('ends_at') and l_body.get('ends_at') is not null and not l_body.get('ends_at').is_null then l_body.get_string('ends_at')
          else null
        end;
        l_starts := case when l_starts_raw is not null then to_timestamp(substr(l_starts_raw, 1, 19), 'YYYY-MM-DD"T"HH24:MI:SS') else null end;
        l_ends := case when l_ends_raw is not null then to_timestamp(substr(l_ends_raw, 1, 19), 'YYYY-MM-DD"T"HH24:MI:SS') else null end;
        FUNO_APP.pkg_admin_content.update_competition_dates(
          p_competition_id => l_body.get_number('competition_id'),
          p_starts_at => l_starts,
          p_ends_at => l_ends,
          p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- POST /funo/admin/competitions/meta
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competitions/meta');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/meta',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
      declare
        l_body json_object_t := json_object_t(:body);
      begin
        FUNO_APP.pkg_admin_content.update_competition_meta(
          p_competition_id => l_body.get_number('competition_id'),
          p_name           => l_body.get_string('name'),
          p_description    => case when l_body.has('description') then l_body.get_string('description') else null end,
          p_status         => case when l_body.has('status') then l_body.get_string('status') else 'ACTIVE' end,
          p_use_location   => case when l_body.has('use_location') then l_body.get_string('use_location') else null end,
          p_show_competitor_location => case when l_body.has('show_competitor_location') then l_body.get_string('show_competitor_location') else null end,
          p_radius_m       => case when l_body.has('radius_m') then l_body.get_number('radius_m') else null end,
          p_updated_by     => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
        );
        :status_code := 200;
        htp.p('{"ok":true}');
      end;
    ]'
  );

  -- GET /funo/admin/competitions/terms?competition_id=..&lang_code=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competitions/terms');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/terms',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.get_competition_terms_json(
          p_competition_id => to_number(:competition_id),
          p_lang_code => :lang_code,
          p_default_terms_text => null,
          o_item_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(nvl(l_json, '{}'));
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/competitions/terms',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/competitions/terms',
    p_method             => 'GET',
    p_name               => 'lang_code',
    p_bind_variable_name => 'lang_code',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
    p_access_method      => 'IN'
  );
  -- POST /funo/admin/competitions/terms
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/terms',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'~
      declare
        l_body json_object_t;
      begin
        l_body := json_object_t.parse(:body_text);
        FUNO_APP.pkg_admin_content.set_competition_terms_text(
          p_competition_id => l_body.get_number('competition_id'),
          p_lang_code => case when l_body.has('lang_code') then l_body.get_string('lang_code') else 'et' end,
          p_terms_text => l_body.get_clob('terms_text'),
          p_updated_by => case when l_body.has('updated_by') then l_body.get_number('updated_by') else null end
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      end;
    ~'
  );

  -- GET /funo/admin/competitions/map-layers?competition_id=..
  ORDS.DEFINE_TEMPLATE(p_module_name => 'funo.api', p_pattern => 'admin/competitions/map-layers');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/map-layers',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'~
      declare
        l_json clob;
      begin
        FUNO_APP.pkg_admin_content.get_participant_map_layers_json(
          p_competition_id => to_number(:competition_id),
          o_items_json => l_json
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"items":' || nvl(l_json, '[]') || '}');
      end;
    ~'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'funo.api',
    p_pattern            => 'admin/competitions/map-layers',
    p_method             => 'GET',
    p_name               => 'competition_id',
    p_bind_variable_name => 'competition_id',
    p_source_type        => 'URI',
    p_param_type         => 'INT',
    p_access_method      => 'IN'
  );

  -- POST /funo/admin/competitions/map-layers
  ORDS.DEFINE_HANDLER(
    p_module_name => 'funo.api',
    p_pattern     => 'admin/competitions/map-layers',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source      => q'~
      declare
        l_body json_object_t;
        l_layers_json clob;
        l_competition_id number;
        l_updated_by number;
        l_layer_codes json_array_t;
      begin
        l_body := json_object_t.parse(:body_text);

        if l_body.has('competition_id') then
          begin
            l_competition_id := l_body.get_number('competition_id');
          exception
            when others then
              begin
                l_competition_id := to_number(l_body.get_string('competition_id'));
              exception
                when others then
                  l_competition_id := null;
              end;
          end;
        end if;

        if l_body.has('updated_by') then
          begin
            l_updated_by := l_body.get_number('updated_by');
          exception
            when others then
              begin
                l_updated_by := to_number(l_body.get_string('updated_by'));
              exception
                when others then
                  l_updated_by := null;
              end;
          end;
        end if;

        l_layers_json := '[]';
        if l_body.has('layer_codes') then
          begin
            l_layer_codes := l_body.get_array('layer_codes');
            if l_layer_codes is not null then
              l_layer_codes.to_clob(l_layers_json);
            end if;
          exception
            when others then
              l_layers_json := '[]';
          end;
        end if;

        FUNO_APP.pkg_admin_content.set_participant_map_layers(
          p_competition_id => l_competition_id,
          p_layer_codes_json => l_layers_json,
          p_updated_by => l_updated_by
        );
        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p('{"ok":true}');
      exception
        when others then
          owa_util.status_line(500, 'Internal Server Error');
          owa_util.mime_header('application/json', false);
          owa_util.http_header_close;
          htp.p(
            json_object(
              'code' value 'MAP_LAYERS_SAVE_FAILED',
              'sqlerrm' value sqlerrm,
              'backtrace' value dbms_utility.format_error_backtrace
            )
          );
      end;
    ~'
  );

  commit;
end;
/
