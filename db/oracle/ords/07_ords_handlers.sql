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
      begin
        l_body := json_object_t.parse(:body_text);

        FUNO_APP.pkg_submissions.submit_answer(
          p_user_id        => l_body.get_number('user_id'),
          p_competition_id => l_body.get_number('competition_id'),
          p_checkpoint_id  => l_body.get_number('checkpoint_id'),
          p_question_id    => l_body.get_number('question_id'),
          p_answer_text    => case when l_body.has('answer_text') then l_body.get_string('answer_text') else null end,
          o_submission_id  => l_submission_id
        );

        owa_util.mime_header('application/json', false);
        owa_util.http_header_close;
        htp.p(json_object('submission_id' value l_submission_id));
      end;
    ]'
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

  commit;
end;
/
