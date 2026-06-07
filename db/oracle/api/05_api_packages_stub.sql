-- 05_api_packages_stub.sql
-- Run as FUNO_APP

create or replace package pkg_auth as
  -- upsert_google_user: Inserts or updates google user data.
  procedure upsert_google_user(
    p_google_sub in varchar2,
    p_email in varchar2,
    p_full_name in varchar2,
    o_user_id out number
  );

  -- resolve_user_for_dev: Resolves and returns an effective identifier or entity.
  procedure resolve_user_for_dev(
    p_user_id in number,
    p_email in varchar2,
    o_user_id out number
  );

  -- has_active_role: Checks whether the requested condition is satisfied.
  procedure has_active_role(
    p_user_id in number,
    p_role_code in varchar2,
    o_has_role out varchar2
  );

  -- get_user_profile: Returns user profile data.
  procedure get_user_profile(
    p_user_id in number,
    o_email out varchar2,
    o_full_name out varchar2
  );
end pkg_auth;
/

create or replace package body pkg_auth as
  -- upsert_google_user: Inserts or updates google user data.
  procedure upsert_google_user(
    p_google_sub in varchar2,
    p_email in varchar2,
    p_full_name in varchar2,
    o_user_id out number
  ) is
  begin
    if p_google_sub is null or p_email is null then
      raise_application_error(-20010, 'google_sub and email are required');
    end if;

    begin
      select u.user_id
        into o_user_id
        from users u
       where u.google_sub = p_google_sub
         and (u.end_date is null or u.end_date > sysdate)
       fetch first 1 row only;

      update users
         set email = p_email,
             full_name = p_full_name,
             updated_at = systimestamp
       where user_id = o_user_id;
    exception
      when no_data_found then
        o_user_id := seq_users.nextval;
        insert into users (
          user_id, email, full_name, google_sub, start_date, created_at
        ) values (
          o_user_id, p_email, p_full_name, p_google_sub, trunc(sysdate), systimestamp
        );
    end;
  end;

  -- resolve_user_for_dev: Resolves and returns an effective identifier or entity.
  procedure resolve_user_for_dev(
    p_user_id in number,
    p_email in varchar2,
    o_user_id out number
  ) is
  begin
    if p_user_id is null and p_email is null then
      o_user_id := seq_users.nextval;
      insert into users (
        user_id, auth_type, start_date, created_at
      ) values (
        o_user_id, 'ANON', trunc(sysdate), systimestamp
      );
      return;
    end if;

    if p_user_id is not null then
      begin
        select u.user_id
          into o_user_id
          from users u
         where u.user_id = p_user_id
           and (u.end_date is null or u.end_date > sysdate)
         fetch first 1 row only;
      exception
        when no_data_found then
          raise_application_error(-20071, 'active user not found');
      end;
    else
      begin
        select u.user_id
          into o_user_id
          from users u
         where lower(u.email) = lower(p_email)
           and (u.end_date is null or u.end_date > sysdate)
         fetch first 1 row only;
      exception
        when no_data_found then
          raise_application_error(-20071, 'active user not found');
      end;
    end if;
  end;

  -- has_active_role: Checks whether the requested condition is satisfied.
  procedure has_active_role(
    p_user_id in number,
    p_role_code in varchar2,
    o_has_role out varchar2
  ) is
    l_cnt number;
  begin
    o_has_role := 'N';
    if p_user_id is null or p_role_code is null then
      return;
    end if;

    select count(*)
      into l_cnt
      from user_roles ur
      join roles r
        on r.role_id = ur.role_id
     where ur.user_id = p_user_id
       and upper(r.role_code) = upper(trim(p_role_code))
       and (r.end_date is null or r.end_date > sysdate)
       and (ur.end_date is null or ur.end_date > sysdate);

    if l_cnt > 0 then
      o_has_role := 'Y';
    end if;
  end;

  -- get_user_profile: Returns user profile data.
  procedure get_user_profile(
    p_user_id in number,
    o_email out varchar2,
    o_full_name out varchar2
  ) is
  begin
    o_email := null;
    o_full_name := null;
    if p_user_id is null then
      return;
    end if;

    begin
      select u.email, u.full_name
        into o_email, o_full_name
        from users u
       where u.user_id = p_user_id
         and (u.end_date is null or u.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        null;
    end;
  end;
end pkg_auth;
/

create or replace package pkg_common as
  c_iso_ts_format constant varchar2(30) := 'YYYY-MM-DD"T"HH24:MI:SS';
  c_checkpoint_type_normal constant varchar2(10) := 'NORMAL';
  c_checkpoint_type_start constant varchar2(10) := 'START';
  c_checkpoint_type_finish constant varchar2(10) := 'FINISH';
  c_checkpoint_start_order constant number := 0;
  c_checkpoint_finish_order constant number := 9999;
  c_competition_type_random constant varchar2(1) := 'R';
  c_competition_type_sequential constant varchar2(1) := 'S';

  -- normalize_checkpoint_type: normalizes null/blank values to NORMAL and uppercases supported special types.
  function normalize_checkpoint_type(
    p_checkpoint_type in varchar2
  ) return varchar2 deterministic;

  -- normalize_competition_type: normalizes null/blank values to R and uppercases supported competition types.
  function normalize_competition_type(
    p_competition_type in varchar2
  ) return varchar2 deterministic;

  -- get_next_ordered_checkpoint_id: Returns the next unanswered NORMAL checkpoint for an S-type competition.
  function get_next_ordered_checkpoint_id(
    p_user_id in number,
    p_competition_id in number
  ) return number;
end pkg_common;
/

create or replace package body pkg_common as
  function normalize_checkpoint_type(
    p_checkpoint_type in varchar2
  ) return varchar2 deterministic is
    l_type varchar2(10) := upper(trim(p_checkpoint_type));
  begin
    if l_type in (c_checkpoint_type_start, c_checkpoint_type_finish, c_checkpoint_type_normal) then
      return l_type;
    end if;
    return c_checkpoint_type_normal;
  end;

  function normalize_competition_type(
    p_competition_type in varchar2
  ) return varchar2 deterministic is
    l_type varchar2(1) := upper(trim(p_competition_type));
  begin
    if l_type = c_competition_type_sequential then
      return c_competition_type_sequential;
    end if;
    return c_competition_type_random;
  end;

  function get_next_ordered_checkpoint_id(
    p_user_id in number,
    p_competition_id in number
  ) return number is
    l_checkpoint_id checkpoints.checkpoint_id%type;
  begin
    begin
      select cp.checkpoint_id
        into l_checkpoint_id
        from checkpoints cp
        join questions q
          on q.checkpoint_id = cp.checkpoint_id
       where cp.competition_id = p_competition_id
         and normalize_checkpoint_type(cp.checkpoint_type) = c_checkpoint_type_normal
         and (cp.end_date is null or cp.end_date > sysdate)
         and (q.end_date is null or q.end_date > sysdate)
         and not exists (
           select 1
             from submissions s
            where s.competition_id = p_competition_id
              and s.user_id = p_user_id
              and s.checkpoint_id = cp.checkpoint_id
              and s.question_id = q.question_id
         )
       order by nvl(cp.order_no, c_checkpoint_finish_order), cp.checkpoint_id
       fetch first 1 row only;
    exception
      when no_data_found then
        l_checkpoint_id := null;
    end;
    return l_checkpoint_id;
  end;
end pkg_common;
/

create or replace package pkg_competitions as
  -- create_competition: Creates a new competition record.
  procedure create_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number
  );

  -- register_to_competition: Performs this business operation according to package rules.
  procedure register_to_competition(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  );

  -- add_organizer: Performs this business operation according to package rules.
  procedure add_organizer(
    p_competition_id in number,
    p_target_user_id in number,
    p_assigned_by in number
  );

  -- register_organizer_by_code: Performs this business operation according to package rules.
  procedure register_organizer_by_code(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  );
end pkg_competitions;
/

create or replace package body pkg_competitions as
  -- create_competition: Creates a new competition record.
  procedure create_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number
  ) is
  begin
    if p_name is null then
      raise_application_error(-20020, 'competition name is required'); -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    end if;

    o_competition_id := seq_competitions.nextval;
    insert into competitions (
      competition_id, name, description, status, show_competitor_location, start_date, created_by, created_at
    ) values (
      o_competition_id, p_name, p_description, 'DRAFT', 'N', trunc(sysdate), p_created_by, systimestamp -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    );
  end;

  -- register_to_competition: Performs this business operation according to package rules.
  procedure register_to_competition(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  ) is
    l_access_code_id competition_access_codes.access_code_id%type;
    l_max_uses competition_access_codes.max_uses%type;
    l_used_count competition_access_codes.used_count%type;
    l_terms_id competition_terms.terms_id%type;
    l_terms_lang_code competition_terms_texts.lang_code%type;
    l_dummy number;
    l_now_utc_ts timestamp;
  begin
    l_now_utc_ts := cast((systimestamp at time zone 'UTC') as timestamp);

    if p_access_code is null then
      raise_application_error(-20030, 'access_code is required'); -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    end if;

    -- Find active and valid access code.
    begin
      select c.access_code_id,
             c.competition_id,
             c.max_uses,
             c.used_count
        into l_access_code_id,
             o_competition_id,
             l_max_uses,
             l_used_count
       from competition_access_codes c
       join competitions comp
         on comp.competition_id = c.competition_id
       where c.code = p_access_code
         and c.code_type = 'COMPETITOR' -- NOSONAR: S1192 repeated literal accepted for script readability/stability
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > l_now_utc_ts)
         and c.status = 'ACTIVE' -- NOSONAR: S1192 repeated literal accepted for script readability/stability
         and (comp.end_date is null or comp.end_date > sysdate)
         and comp.status = 'ACTIVE'
         and (comp.starts_at is null or comp.starts_at <= l_now_utc_ts)
         and (comp.ends_at is null or comp.ends_at > l_now_utc_ts)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20031, 'invalid or inactive access code'); -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    end;

    if l_max_uses is not null and l_used_count >= l_max_uses then
      raise_application_error(-20032, 'access code usage limit reached'); -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    end if;

    -- Resolve active competition terms required by participants schema.
    begin
      select t.terms_id
        into l_terms_id
        from competition_terms t
       where t.competition_id = o_competition_id
         and t.status = 'ACTIVE'
         and (t.end_date is null or t.end_date > sysdate)
       order by t.version_no desc, t.terms_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        insert into competition_terms (
          terms_id,
          competition_id,
          version_no,
          status,
          start_date,
          created_by,
          created_at
        ) values (
          seq_competition_terms.nextval,
          o_competition_id,
          1,
          'ACTIVE',
          trunc(sysdate),
          p_user_id,
          systimestamp
        )
        returning terms_id into l_terms_id;

        insert into competition_terms_texts (
          terms_text_id,
          terms_id,
          lang_code,
          terms_text,
          start_date,
          created_by,
          created_at
        ) values (
          seq_competition_terms_texts.nextval,
          l_terms_id,
          'et',
          'Kasutustingimused',
          trunc(sysdate),
          p_user_id,
          systimestamp
        );
    end;

    begin
      select lower(tt.lang_code)
        into l_terms_lang_code
        from competition_terms_texts tt
       where tt.terms_id = l_terms_id
         and (tt.end_date is null or tt.end_date > sysdate)
       order by case when lower(tt.lang_code) = 'et' then 0 else 1 end,
                tt.lang_code
       fetch first 1 row only;
    exception
      when no_data_found then
        l_terms_lang_code := 'et';
        insert into competition_terms_texts (
          terms_text_id,
          terms_id,
          lang_code,
          terms_text,
          start_date,
          created_by,
          created_at
        ) values (
          seq_competition_terms_texts.nextval,
          l_terms_id,
          l_terms_lang_code,
          'Kasutustingimused',
          trunc(sysdate),
          p_user_id,
          systimestamp
        );
    end;

    -- Prevent duplicate active participation.
    begin
      select 1
        into l_dummy
        from competition_participants p
       where p.competition_id = o_competition_id
         and p.user_id = p_user_id
         and (p.end_date is null or p.end_date > sysdate)
       fetch first 1 row only;

      raise_application_error(-20033, 'user is already an active participant for this competition');
    exception
      when no_data_found then
        null;
    end;

    insert into competition_participants (
      competition_participant_id,
      competition_id,
      user_id,
      access_code_id,
      alias_display,
      terms_id,
      terms_lang_code,
      terms_accepted_at,
      status,
      start_date,
      joined_at
    ) values (
      seq_competition_participants.nextval,
      o_competition_id,
      p_user_id,
      l_access_code_id,
      'participant-' || to_char(p_user_id),
      l_terms_id,
      l_terms_lang_code,
      systimestamp,
      'ACTIVE',
      trunc(sysdate),
      systimestamp
    );

    update competition_access_codes
       set used_count = used_count + 1
     where access_code_id = l_access_code_id;
  end;

  -- add_organizer: Performs this business operation according to package rules.
  procedure add_organizer(
    p_competition_id in number,
    p_target_user_id in number,
    p_assigned_by in number
  ) is
    l_dummy number;
  begin
    if p_competition_id is null or p_target_user_id is null or p_assigned_by is null then
      raise_application_error(-20040, 'competition_id, target_user_id and assigned_by are required');
    end if;

    -- Assigner must be existing active organizer for this competition.
    begin
      select 1
        into l_dummy
        from competition_organizers co
       where co.competition_id = p_competition_id
         and co.user_id = p_assigned_by
         and (co.end_date is null or co.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20041, 'assigned_by is not an active organizer for this competition');
    end;

    -- Prevent duplicate active organizer relation.
    begin
      select 1
        into l_dummy
        from competition_organizers co
       where co.competition_id = p_competition_id
         and co.user_id = p_target_user_id
         and (co.end_date is null or co.end_date > sysdate)
       fetch first 1 row only;

      raise_application_error(-20042, 'target user is already an active organizer for this competition');
    exception
      when no_data_found then
        null;
    end;

    insert into competition_organizers (
      competition_organizer_id,
      competition_id,
      user_id,
      start_date,
      assigned_by,
      assigned_at
    ) values (
      seq_competition_organizers.nextval,
      p_competition_id,
      p_target_user_id,
      trunc(sysdate),
      p_assigned_by,
      systimestamp
    );
  end;

  -- register_organizer_by_code: Performs this business operation according to package rules.
  procedure register_organizer_by_code(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  ) is
    l_access_code_id competition_access_codes.access_code_id%type;
    l_dummy number;
    l_now_utc_ts timestamp;
  begin
    l_now_utc_ts := cast((systimestamp at time zone 'UTC') as timestamp);

    if p_user_id is null or p_access_code is null then
      raise_application_error(-20080, 'user_id and access_code are required');
    end if;

    begin
      select c.access_code_id, c.competition_id
        into l_access_code_id, o_competition_id
        from competition_access_codes c
        join competitions comp on comp.competition_id = c.competition_id
       where c.code = p_access_code
         and c.code_type = 'ORGANIZER' -- NOSONAR: S1192 repeated literal accepted for script readability/stability
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > l_now_utc_ts)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and (comp.ends_at is null or comp.ends_at > l_now_utc_ts)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20081, 'invalid or inactive organizer access code');
    end;

    begin
      select 1
        into l_dummy
        from competition_organizers co
       where co.competition_id = o_competition_id
         and co.user_id = p_user_id
         and (co.end_date is null or co.end_date > sysdate)
       fetch first 1 row only;
      raise_application_error(-20082, 'user is already organizer for this competition');
    exception
      when no_data_found then
        null;
    end;

    insert into competition_organizers (
      competition_organizer_id,
      competition_id,
      user_id,
      start_date,
      assigned_by,
      assigned_at
    ) values (
      seq_competition_organizers.nextval,
      o_competition_id,
      p_user_id,
      trunc(sysdate),
      null,
      systimestamp
    );
  end;
end pkg_competitions;
/

create or replace package pkg_questions as
  -- create_question: Creates a new question record.
  procedure create_question(
    p_checkpoint_id in number,
    p_question_text in varchar2,
    p_question_type in varchar2,
    p_points in number,
    p_created_by in number,
    o_question_id out number
  );

  -- update_question: Updates existing data for question.
  procedure update_question(
    p_question_id in number,
    p_checkpoint_id in number,
    p_question_type in varchar2,
    p_input_type in varchar2,
    p_input_max_length in number,
    p_input_pattern in varchar2,
    p_points in number,
    p_lang_code in varchar2,
    p_question_text in varchar2,
    p_updated_by in number
  );
end pkg_questions;
/

create or replace package body pkg_questions as
  -- create_question: Creates a new question record.
  procedure create_question(
    p_checkpoint_id in number,
    p_question_text in varchar2,
    p_question_type in varchar2,
    p_points in number,
    p_created_by in number,
    o_question_id out number
  ) is
  begin
    if p_checkpoint_id is null or p_question_text is null or p_question_type is null then
      raise_application_error(-20050, 'checkpoint_id, question_text and question_type are required');
    end if;

    o_question_id := seq_questions.nextval;
    insert into questions (
      question_id,
      checkpoint_id,
      question_type,
      input_type,
      points,
      status,
      start_date,
      created_by,
      created_at
    ) values (
      o_question_id,
      p_checkpoint_id,
      p_question_type,
      'TEXT',
      nvl(p_points, 0),
      'ACTIVE',
      trunc(sysdate),
      p_created_by,
      systimestamp
    );

    insert into question_texts (
      question_text_id,
      question_id,
      lang_code,
      question_text,
      start_date,
      created_by,
      created_at
    ) values (
      seq_question_texts.nextval,
      o_question_id,
      'et',
      p_question_text,
      trunc(sysdate),
      p_created_by,
      systimestamp
    );
  end;

  -- update_question: Updates existing data for question.
  procedure update_question(
    p_question_id in number,
    p_checkpoint_id in number,
    p_question_type in varchar2,
    p_input_type in varchar2,
    p_input_max_length in number,
    p_input_pattern in varchar2,
    p_points in number,
    p_lang_code in varchar2,
    p_question_text in varchar2,
    p_updated_by in number
  ) is
    l_lang varchar2(10);
  begin
    if p_question_id is null or p_checkpoint_id is null or p_question_type is null or p_question_text is null then
      raise_application_error(-20052, 'question_id, checkpoint_id, question_type and question_text are required');
    end if;

    l_lang := nvl(p_lang_code, 'et');

    update questions
       set checkpoint_id = p_checkpoint_id,
           question_type = p_question_type,
           input_type = p_input_type,
           input_max_length = p_input_max_length,
           input_pattern = p_input_pattern,
           points = nvl(p_points, 0),
           updated_by = p_updated_by,
           updated_at = systimestamp
     where question_id = p_question_id
       and (end_date is null or end_date > sysdate);

    update question_texts
       set question_text = p_question_text,
           updated_by = p_updated_by,
           updated_at = systimestamp
     where question_id = p_question_id
       and lower(lang_code) = lower(l_lang)
       and (end_date is null or end_date > sysdate);

    if sql%rowcount = 0 then
      insert into question_texts (
        question_text_id,
        question_id,
        lang_code,
        question_text,
        start_date,
        created_by,
        created_at
      ) values (
        seq_question_texts.nextval,
        p_question_id,
        l_lang,
        p_question_text,
        trunc(sysdate),
        p_updated_by,
        systimestamp
      );
    end if;
  end;
end pkg_questions;
/

create or replace package pkg_results as
  -- get_total_elapsed_seconds: Returns competition elapsed seconds for one competitor.
  function get_total_elapsed_seconds(
    p_competition_id in number,
    p_user_id in number
  ) return number;

  -- get_distance_available: Returns whether at least two usable geo points exist for distance calculation.
  function get_distance_available(
    p_competition_id in number,
    p_user_id in number
  ) return varchar2;

  -- get_total_distance_m: Returns cumulative as-the-crow-flies distance in meters for one competitor.
  function get_total_distance_m(
    p_competition_id in number,
    p_user_id in number
  ) return number;

  -- get_competition_rank: Returns competitor rank using competition ordering rules.
  function get_competition_rank(
    p_competition_id in number,
    p_user_id in number
  ) return number;

  -- get_competition_score: Returns competition score for one competitor.
  procedure get_competition_score(
    p_competition_id in number,
    p_user_id in number,
    o_score out number
  );

  -- get_competition_leaderboard: Returns organizer leaderboard payload for one competition.
  procedure get_competition_leaderboard(
    p_competition_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  );

  -- get_participant_submissions: Returns organizer participant submissions timeline and summary.
  procedure get_participant_submissions(
    p_competition_id in number,
    p_user_id in number,
    p_requester_user_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_access_granted out varchar2,
    o_items_json out clob,
    o_total_elapsed_seconds out number,
    o_total_distance_m out number,
    o_distance_available out varchar2
  );

  -- get_submission_detail: Returns one organizer-visible submission detail payload.
  procedure get_submission_detail(
    p_competition_id in number,
    p_user_id in number,
    p_submission_id in number,
    p_requester_user_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_access_granted out varchar2,
    o_item_json out clob
  );

  -- get_checkpoint_results: Returns organizer checkpoint aggregate results.
  procedure get_checkpoint_results(
    p_competition_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  );

  -- get_checkpoint_responders: Returns organizer-visible responders for one checkpoint.
  procedure get_checkpoint_responders(
    p_competition_id in number,
    p_checkpoint_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  );
end pkg_results;
/

create or replace package pkg_submissions as
  -- normalize_text: Normalizes input value(s) according to the expected format.
  function normalize_text(
    p_value in varchar2,
    p_mode in varchar2
  ) return varchar2 deterministic;

  -- submit_answer: Performs this business operation according to package rules.
  procedure submit_answer(
    p_user_id in number,
    p_competition_id in number,
    p_checkpoint_id in number,
    p_question_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    p_answer_text in clob,
    p_selected_option_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_submission_id out number,
    o_is_correct out varchar2,
    o_awarded_points out number,
    o_total_score out number,
    o_correct_answer_texts_json out clob,
    o_other_correct_answer_texts_json out clob,
    o_total_elapsed_seconds out number,
    o_total_distance_m out number,
    o_distance_display_allowed out varchar2,
    o_current_rank out number
  );
end pkg_submissions;
/

create or replace package body pkg_submissions as
  -- normalize_text: Normalizes input value(s) according to the expected format.
  function normalize_text(
    p_value in varchar2,
    p_mode in varchar2
  ) return varchar2 deterministic is
    l_mode varchar2(30) := upper(nvl(p_mode, 'EXACT'));
    l_val varchar2(4000) := nvl(p_value, '');
  begin
    if l_mode = 'TRIM_UPPER' then
      return upper(trim(l_val));
    elsif l_mode = 'LOWER_TRIM' then
      return lower(trim(l_val));
    elsif l_mode = 'NUMERIC' then
      return regexp_replace(trim(replace(l_val, ',', '.')), '[^0-9\.\-]', '');
    else
      return l_val;
    end if;
  end;

  -- submit_answer: Performs this business operation according to package rules.
  procedure submit_answer(
    p_user_id in number,
    p_competition_id in number,
    p_checkpoint_id in number,
    p_question_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    p_answer_text in clob,
    p_selected_option_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_submission_id out number,
    o_is_correct out varchar2,
    o_awarded_points out number,
    o_total_score out number,
    o_correct_answer_texts_json out clob,
    o_other_correct_answer_texts_json out clob,
    o_total_elapsed_seconds out number,
    o_total_distance_m out number,
    o_distance_display_allowed out varchar2,
    o_current_rank out number
  ) is
    l_dummy number;
    l_question_type questions.question_type%type;
    l_input_type questions.input_type%type;
    l_checkpoint_type checkpoints.checkpoint_type%type;
    l_awarded_points questions.points%type := 0;
    l_wrong_points questions.wrong_points%type := 0;
    l_is_correct varchar2(1) := 'N';
    l_normalized_answer varchar2(4000);
    l_correct_count number := 0;
    l_comp_type varchar2(1) := pkg_common.c_competition_type_random;
    l_start_exists number := 0;
    l_start_answered number := 0;
    l_finish_answered number := 0;
    l_next_ordered_checkpoint_id checkpoints.checkpoint_id%type;
    l_lang varchar2(10);
    l_fallback_lang varchar2(10);
  begin
    if p_user_id is null or p_competition_id is null or p_checkpoint_id is null or p_question_id is null then
      raise_application_error(-20060, 'user_id, competition_id, checkpoint_id and question_id are required');
    end if;

    begin
      select 1
        into l_dummy
        from competition_participants cp
       where cp.competition_id = p_competition_id
         and cp.user_id = p_user_id
         and (cp.end_date is null or cp.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20061, 'user is not an active participant of this competition');
    end;

    begin
      select q.question_type,
             q.input_type,
             q.points,
             q.wrong_points,
             pkg_common.normalize_checkpoint_type(cp.checkpoint_type)
        into l_question_type,
             l_input_type,
             l_awarded_points,
             l_wrong_points,
             l_checkpoint_type
        from questions q
        join checkpoints cp
          on cp.checkpoint_id = q.checkpoint_id
       where q.question_id = p_question_id
         and q.checkpoint_id = p_checkpoint_id
         and cp.competition_id = p_competition_id
         and (cp.end_date is null or cp.end_date > sysdate)
         and (q.end_date is null or q.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20062, 'question not found or inactive');
    end;

    begin
      select pkg_common.normalize_competition_type(c.type)
        into l_comp_type
        from competitions c
       where c.competition_id = p_competition_id
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        l_comp_type := pkg_common.c_competition_type_random;
    end;

    l_lang := lower(nvl(trim(p_lang_code), 'et'));
    l_fallback_lang := lower(nvl(trim(p_default_lang_code), 'et'));
    if l_fallback_lang is null then
      l_fallback_lang := 'et';
    end if;
    if l_fallback_lang = l_lang then
      l_fallback_lang := null;
    end if;

    select count(*)
      into l_start_exists
      from checkpoints cp
     where cp.competition_id = p_competition_id
       and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
       and (cp.end_date is null or cp.end_date > sysdate);

    if l_start_exists > 0 then
      select count(*)
        into l_start_answered
        from submissions s
        join checkpoints cp
          on cp.checkpoint_id = s.checkpoint_id
       where s.competition_id = p_competition_id
         and s.user_id = p_user_id
         and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
         and (cp.end_date is null or cp.end_date > sysdate);

      if l_start_answered = 0 and l_checkpoint_type <> pkg_common.c_checkpoint_type_start then
        raise_application_error(-20065, 'start checkpoint must be answered first');
      end if;
    end if;

    select count(*)
      into l_finish_answered
      from submissions s
      join checkpoints cp
        on cp.checkpoint_id = s.checkpoint_id
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id
       and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_finish
       and (cp.end_date is null or cp.end_date > sysdate);

    if l_finish_answered > 0 then
      raise_application_error(-20066, 'finish checkpoint has already been answered');
    end if;

    if l_comp_type = pkg_common.c_competition_type_sequential
       and l_checkpoint_type <> pkg_common.c_checkpoint_type_start then
      l_next_ordered_checkpoint_id := pkg_common.get_next_ordered_checkpoint_id(
        p_user_id => p_user_id,
        p_competition_id => p_competition_id
      );

      if l_next_ordered_checkpoint_id is not null then
        if l_checkpoint_type <> pkg_common.c_checkpoint_type_normal
           or p_checkpoint_id <> l_next_ordered_checkpoint_id then
          raise_application_error(-20067, 'checkpoint must be answered in the configured order');
        end if;
      elsif l_checkpoint_type <> pkg_common.c_checkpoint_type_finish then
        raise_application_error(-20067, 'checkpoint must be answered in the configured order');
      end if;
    end if;

    if l_question_type = 'SINGLE_CHOICE' then -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      if p_selected_option_id is null then
        raise_application_error(-20063, 'selected_option_id is required for SINGLE_CHOICE question');
      end if;

      select count(*)
        into l_correct_count
        from question_options qo
       where qo.option_id = p_selected_option_id
         and qo.question_id = p_question_id
         and qo.is_correct = 'Y'
         and (qo.end_date is null or qo.end_date > sysdate);

      if l_correct_count > 0 then
        l_is_correct := 'Y';
      end if;
    else
      if p_answer_text is null then
        raise_application_error(-20064, 'answer_text is required for TEXT question');
      end if;

      l_normalized_answer := dbms_lob.substr(p_answer_text, 4000, 1);

      select count(*)
        into l_correct_count
        from question_answers qa
       where qa.question_id = p_question_id
         and qa.is_correct = 'Y'
         and (qa.end_date is null or qa.end_date > sysdate)
         and (
               normalize_text(qa.answer_value, qa.normalize_mode)
                 = normalize_text(l_normalized_answer, qa.normalize_mode)
          );

      if l_correct_count > 0 then
        l_is_correct := 'Y';
      end if;
    end if;

    if l_is_correct = 'N' then
      l_awarded_points := nvl(l_wrong_points, 0);
    end if;

    o_submission_id := seq_submissions.nextval;
    insert into submissions (
      submission_id,
      competition_id,
      checkpoint_id,
      question_id,
      user_id,
      answer_text,
      selected_option_id,
      latitude,
      longitude,
      radius_m,
      awarded_points,
      is_correct,
      submitted_at,
      evaluated_at
    ) values (
      o_submission_id,
      p_competition_id,
      p_checkpoint_id,
      p_question_id,
      p_user_id,
      p_answer_text,
      p_selected_option_id,
      p_latitude,
      p_longitude,
      p_radius_m,
      l_awarded_points,
      l_is_correct,
      systimestamp,
      systimestamp
    );

    o_is_correct := l_is_correct;
    o_awarded_points := nvl(l_awarded_points, 0);

    select nvl(sum(nvl(s.awarded_points, 0)), 0)
      into o_total_score
      from submissions s
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id;

    if l_question_type = 'SINGLE_CHOICE' then
      select coalesce(
               json_arrayagg(x.option_text returning clob),
               to_clob('[]')
             )
        into o_correct_answer_texts_json
        from (
          select nvl(
                   (
                     select qot_et.option_text
                       from question_option_texts qot_et
                      where qot_et.option_id = qo.option_id
                        and lower(qot_et.lang_code) = l_lang
                        and (qot_et.end_date is null or qot_et.end_date > sysdate)
                      fetch first 1 row only
                   ),
                   nvl(
                     (
                       select qot_f.option_text
                         from question_option_texts qot_f
                        where qot_f.option_id = qo.option_id
                          and lower(qot_f.lang_code) = l_fallback_lang
                          and (qot_f.end_date is null or qot_f.end_date > sysdate)
                        fetch first 1 row only
                     ),
                     qo.option_code
                   )
                 ) as option_text
            from question_options qo
           where qo.question_id = p_question_id
             and qo.is_correct = 'Y'
             and (qo.end_date is null or qo.end_date > sysdate)
           order by nvl(qo.order_no, qo.option_id) asc, qo.option_id asc
        ) x;

      if l_is_correct = 'Y' then
        select coalesce(
                 json_arrayagg(x.option_text returning clob),
                 to_clob('[]')
               )
          into o_other_correct_answer_texts_json
          from (
            select nvl(
                     (
                       select qot_et.option_text
                         from question_option_texts qot_et
                        where qot_et.option_id = qo.option_id
                          and lower(qot_et.lang_code) = l_lang
                          and (qot_et.end_date is null or qot_et.end_date > sysdate)
                        fetch first 1 row only
                     ),
                     nvl(
                       (
                         select qot_f.option_text
                           from question_option_texts qot_f
                          where qot_f.option_id = qo.option_id
                            and lower(qot_f.lang_code) = l_fallback_lang
                            and (qot_f.end_date is null or qot_f.end_date > sysdate)
                          fetch first 1 row only
                       ),
                       qo.option_code
                     )
                   ) as option_text
              from question_options qo
             where qo.question_id = p_question_id
               and qo.is_correct = 'Y'
               and qo.option_id <> p_selected_option_id
               and (qo.end_date is null or qo.end_date > sysdate)
              order by nvl(qo.order_no, qo.option_id) asc, qo.option_id asc
          ) x;
      else
        o_other_correct_answer_texts_json := to_clob('[]');
      end if;
    else
      select coalesce(
               json_arrayagg(x.answer_value returning clob),
               to_clob('[]')
             )
        into o_correct_answer_texts_json
        from (
          select qa.answer_value
            from question_answers qa
           where qa.question_id = p_question_id
             and qa.is_correct = 'Y'
             and (qa.end_date is null or qa.end_date > sysdate)
           order by qa.answer_id asc
        ) x;

      if l_is_correct = 'Y' then
        select coalesce(
                 json_arrayagg(x.answer_value returning clob),
                 to_clob('[]')
               )
          into o_other_correct_answer_texts_json
          from (
            select qa.answer_value
              from question_answers qa
             where qa.question_id = p_question_id
               and qa.is_correct = 'Y'
               and (qa.end_date is null or qa.end_date > sysdate)
               and normalize_text(qa.answer_value, qa.normalize_mode)
                   <> normalize_text(l_normalized_answer, qa.normalize_mode)
             order by qa.answer_id asc
          ) x;
      else
        o_other_correct_answer_texts_json := to_clob('[]');
      end if;
    end if;

    o_total_elapsed_seconds := pkg_results.get_total_elapsed_seconds(
      p_competition_id => p_competition_id,
      p_user_id => p_user_id
    );
    o_current_rank := pkg_results.get_competition_rank(
      p_competition_id => p_competition_id,
      p_user_id => p_user_id
    );

    if p_latitude is not null and p_longitude is not null then
      o_distance_display_allowed := pkg_results.get_distance_available(
        p_competition_id => p_competition_id,
        p_user_id => p_user_id
      );
      if o_distance_display_allowed = 'Y' then
        o_total_distance_m := pkg_results.get_total_distance_m(
          p_competition_id => p_competition_id,
          p_user_id => p_user_id
        );
      else
        o_total_distance_m := null;
      end if;
    else
      o_distance_display_allowed := 'N';
      o_total_distance_m := null;
    end if;
  end;
end pkg_submissions;
/

create or replace package pkg_i18n as
  -- get_translations_json: Returns a JSON object for the requested translations.
  procedure get_translations_json(
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_items_json out clob
  );
end pkg_i18n;
/

create or replace package body pkg_i18n as
  -- get_translations_json: Returns a JSON object for the requested translations.
  procedure get_translations_json(
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_items_json out clob
  ) is
  begin
    select json_objectagg(x.translation_key value x.text_value returning clob)
      into o_items_json
      from (
        select translation_key, text_value
          from (
            select t.translation_key,
                   t.text_value,
                   row_number() over (
                     partition by t.translation_key
                     order by case
                                when lower(t.lang_code) = lower(p_lang_code) then 1
                                when lower(t.lang_code) = lower(p_default_lang_code) then 2
                                else 9
                              end
                   ) as rn
              from translations t
             where (t.end_date is null or t.end_date > sysdate)
               and lower(t.lang_code) in (lower(p_lang_code), lower(p_default_lang_code))
          )
         where rn = 1
      ) x;

    if o_items_json is null then
      o_items_json := '{}';
    end if;
  end;
end pkg_i18n;
/

create or replace package body pkg_results as
  c_json_question_text constant varchar2(30) := 'question_text'; -- NOSONAR: S1192 repeated literal accepted for script readability/stability

  function get_total_elapsed_seconds(
    p_competition_id in number,
    p_user_id in number
  ) return number is
    l_total_elapsed_seconds number;
  begin
    select case
             when count(*) >= 2 then round((max(cast(s.submitted_at as date)) - min(cast(s.submitted_at as date))) * 86400)
             else null
           end
      into l_total_elapsed_seconds
      from submissions s
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id
       and s.submitted_at is not null;
    return l_total_elapsed_seconds;
  end;

  function get_distance_available(
    p_competition_id in number,
    p_user_id in number
  ) return varchar2 is
    l_use_location varchar2(1) := 'N';
    l_geo_count number := 0;
  begin
    begin
      select case when nvl(c.use_location, 'N') = 'Y' then 'Y' else 'N' end
        into l_use_location
        from competitions c
       where c.competition_id = p_competition_id;
    exception
      when no_data_found then
        return 'N';
    end;

    if l_use_location <> 'Y' then
      return 'N';
    end if;

    select count(*)
      into l_geo_count
      from (
        select coalesce(s.latitude, cp.latitude) as effective_latitude,
               coalesce(s.longitude, cp.longitude) as effective_longitude
          from submissions s
          join checkpoints cp
            on cp.checkpoint_id = s.checkpoint_id
         where s.competition_id = p_competition_id
           and s.user_id = p_user_id
           and s.submitted_at is not null
           and coalesce(s.latitude, cp.latitude) is not null
           and coalesce(s.longitude, cp.longitude) is not null
      ) geo;

    return case when l_geo_count >= 2 then 'Y' else 'N' end;
  end;

  function get_total_distance_m(
    p_competition_id in number,
    p_user_id in number
  ) return number is
    l_total_distance_m number;
  begin
    if get_distance_available(p_competition_id => p_competition_id, p_user_id => p_user_id) <> 'Y' then
      return null;
    end if;

    select round(sum(
             6371000 * 2 * asin(
               sqrt(
                 power(sin((g.effective_latitude - g.prev_latitude) * 0.008726646259971648), 2) +
                 cos(g.prev_latitude * 0.017453292519943295) *
                 cos(g.effective_latitude * 0.017453292519943295) *
                 power(sin((g.effective_longitude - g.prev_longitude) * 0.008726646259971648), 2)
               )
             )
           ))
      into l_total_distance_m
      from (
        select x.effective_latitude,
               x.effective_longitude,
               lag(x.effective_latitude) over (order by x.submitted_at asc, x.submission_id asc) as prev_latitude,
               lag(x.effective_longitude) over (order by x.submitted_at asc, x.submission_id asc) as prev_longitude
          from (
            select s.submission_id,
                   s.submitted_at,
                   coalesce(s.latitude, cp.latitude) as effective_latitude,
                   coalesce(s.longitude, cp.longitude) as effective_longitude
              from submissions s
              join checkpoints cp
                on cp.checkpoint_id = s.checkpoint_id
             where s.competition_id = p_competition_id
               and s.user_id = p_user_id
               and s.submitted_at is not null
               and coalesce(s.latitude, cp.latitude) is not null
               and coalesce(s.longitude, cp.longitude) is not null
          ) x
      ) g
     where g.prev_latitude is not null
       and g.prev_longitude is not null;

    return l_total_distance_m;
  end;

  function get_competition_rank(
    p_competition_id in number,
    p_user_id in number
  ) return number is
    l_rank number;
  begin
    select x.rank_no
      into l_rank
      from (
        select y.user_id,
               rank() over (
                 order by
                   y.score desc,
                   case when y.total_elapsed_seconds is null then 1 else 0 end asc,
                   y.total_elapsed_seconds asc
               ) as rank_no
          from (
            select s.user_id,
                   nvl(sum(nvl(s.awarded_points, 0)), 0) as score,
                   case
                     when count(s.submitted_at) >= 2 then round((max(cast(s.submitted_at as date)) - min(cast(s.submitted_at as date))) * 86400)
                     else null
                   end as total_elapsed_seconds
              from submissions s
             where s.competition_id = p_competition_id
             group by s.user_id
          ) y
      ) x
     where x.user_id = p_user_id;
    return l_rank;
  exception
    when no_data_found then
      return null;
  end;

  -- get_competition_score: Returns competition score data.
  procedure get_competition_score(
    p_competition_id in number,
    p_user_id in number,
    o_score out number
  ) is
  begin
    select nvl(sum(nvl(s.awarded_points, 0)), 0)
      into o_score
      from submissions s
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id;
  end;

  -- get_competition_leaderboard: Returns competition leaderboard data.
  procedure get_competition_leaderboard(
    p_competition_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  ) is
    l_is_organizer number := 0;
  begin
    select count(*)
      into l_is_organizer
      from competition_organizers co
     where co.competition_id = p_competition_id
       and co.user_id = p_requester_user_id
       and (co.end_date is null or co.end_date > sysdate);

    if l_is_organizer = 0 then
      o_access_granted := 'N';
      o_items_json := '[]';
      return;
    end if;
    o_access_granted := 'Y';

    select json_arrayagg(
             json_object(
               'user_id' value x.user_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'competitor_name' value x.competitor_name, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'answered_checkpoints' value x.answered_checkpoints,
               'score' value x.score,
               'last_checkpoint' value x.last_checkpoint,
               'total_elapsed_seconds' value x.total_elapsed_seconds,
               'total_distance_m' value x.total_distance_m,
               'last_submission_at' value case
                  when x.last_submission_at is not null then to_char(x.last_submission_at, pkg_common.c_iso_ts_format)
                 else null
               end
             ) returning clob
           )
      into o_items_json
      from (
        select s.user_id,
               nvl(max(cp.alias_display), to_char(s.user_id)) as competitor_name,
               count(distinct s.checkpoint_id) as answered_checkpoints,
               nvl(sum(nvl(s.awarded_points, 0)), 0) as score,
               max(case when ls.rn = 1 then c.title end) as last_checkpoint,
               max(s.submitted_at) as last_submission_at,
               case
                 when count(s.submitted_at) >= 2 then round((max(cast(s.submitted_at as date)) - min(cast(s.submitted_at as date))) * 86400)
                 else null
               end as total_elapsed_seconds,
               case
                 when nvl(max(cc.use_location), 'N') = 'Y' then (
                   select case
                            when count(*) >= 2 then round(sum(
                              6371000 * 2 * asin(
                                sqrt(
                                  power(sin((g.effective_latitude - g.prev_latitude) * 0.008726646259971648), 2) +
                                  cos(g.prev_latitude * 0.017453292519943295) *
                                  cos(g.effective_latitude * 0.017453292519943295) *
                                  power(sin((g.effective_longitude - g.prev_longitude) * 0.008726646259971648), 2)
                                )
                              )
                            ))
                            else null
                          end
                     from (
                       select y.effective_latitude,
                              y.effective_longitude,
                              lag(y.effective_latitude) over (order by y.submitted_at asc, y.submission_id asc) as prev_latitude,
                              lag(y.effective_longitude) over (order by y.submitted_at asc, y.submission_id asc) as prev_longitude
                         from (
                           select sx.submission_id,
                                  sx.submitted_at,
                                  coalesce(sx.latitude, cpx.latitude) as effective_latitude,
                                  coalesce(sx.longitude, cpx.longitude) as effective_longitude
                             from submissions sx
                             join checkpoints cpx
                               on cpx.checkpoint_id = sx.checkpoint_id
                            where sx.competition_id = p_competition_id
                              and sx.user_id = s.user_id
                              and sx.submitted_at is not null
                              and coalesce(sx.latitude, cpx.latitude) is not null
                              and coalesce(sx.longitude, cpx.longitude) is not null
                         ) y
                     ) g
                    where g.prev_latitude is not null
                      and g.prev_longitude is not null
                 )
                 else null
               end as total_distance_m
          from submissions s
          join competitions cc
            on cc.competition_id = s.competition_id
          left join checkpoints c
            on c.checkpoint_id = s.checkpoint_id
          left join (
            select p.competition_id,
                   p.user_id,
                   p.alias_display,
                   row_number() over (
                     partition by p.competition_id, p.user_id
                     order by nvl(p.joined_at, timestamp '1900-01-01 00:00:00') desc, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
                              p.competition_participant_id desc
                   ) as rn
              from competition_participants p
          ) cp
            on cp.competition_id = s.competition_id
           and cp.user_id = s.user_id
           and cp.rn = 1
          left join (
            select sx.competition_id,
                   sx.user_id,
                   sx.checkpoint_id,
                   row_number() over (
                     partition by sx.competition_id, sx.user_id
                     order by sx.submitted_at desc, sx.submission_id desc
                   ) as rn
              from submissions sx
          ) ls
            on ls.competition_id = s.competition_id
           and ls.user_id = s.user_id
           and ls.checkpoint_id = s.checkpoint_id
         where s.competition_id = p_competition_id
         group by s.user_id
         order by
           score desc,
           case when total_elapsed_seconds is null then 1 else 0 end asc,
           total_elapsed_seconds asc,
            s.user_id asc
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- get_participant_submissions: Returns participant submissions data.
  procedure get_participant_submissions(
    p_competition_id in number,
    p_user_id in number,
    p_requester_user_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_access_granted out varchar2,
    o_items_json out clob,
    o_total_elapsed_seconds out number,
    o_total_distance_m out number,
    o_distance_available out varchar2
  ) is
    l_lang varchar2(10);
    l_fallback_lang varchar2(10);
    l_is_organizer number := 0;
  begin
    select count(*)
      into l_is_organizer
      from competition_organizers co
     where co.competition_id = p_competition_id
       and co.user_id = p_requester_user_id
       and (co.end_date is null or co.end_date > sysdate);

    if l_is_organizer = 0 then
      o_access_granted := 'N';
      o_items_json := '[]';
      o_total_elapsed_seconds := null;
      o_total_distance_m := null;
      o_distance_available := 'N';
      return;
    end if;
    o_access_granted := 'Y';

    l_lang := lower(nvl(trim(p_lang_code), 'et'));
    l_fallback_lang := lower(nvl(trim(p_default_lang_code), 'et'));
    if l_fallback_lang is null then
      l_fallback_lang := 'et';
    end if;
    if l_fallback_lang = l_lang then
      l_fallback_lang := null;
    end if;

    select json_arrayagg(
             json_object(
               'checkpoint_title' value x.checkpoint_title, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'submission_id' value x.submission_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'submitted_at' value case -- NOSONAR: S1192 repeated literal accepted for script readability/stability
                  when x.submitted_at is not null then to_char(x.submitted_at, pkg_common.c_iso_ts_format)
                 else null
               end,
               'delta_from_prev_seconds' value x.delta_from_prev_seconds,
               'awarded_points' value x.awarded_points, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'answer_text' value x.answer_text,
               'is_correct' value x.is_correct -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             ) returning clob
           )
      into o_items_json
      from (
        with base_rows as (
          select cp.title as checkpoint_title,
                 s.submission_id,
                 s.submitted_at,
                 nvl(s.awarded_points, 0) as awarded_points,
                 case
                   when q.question_type = 'SINGLE_CHOICE' then nvl(
                     (
                       select qot_et.option_text
                         from question_option_texts qot_et
                        where qot_et.option_id = s.selected_option_id
                          and lower(qot_et.lang_code) = l_lang
                        fetch first 1 row only
                     ),
                     nvl(
                       (
                         select qot_en.option_text
                           from question_option_texts qot_en
                          where qot_en.option_id = s.selected_option_id
                            and lower(qot_en.lang_code) = l_fallback_lang
                          fetch first 1 row only
                       ),
                       '---'
                     )
                   )
                   else dbms_lob.substr(s.answer_text, 4000, 1)
                 end as answer_text,
                 case when nvl(s.is_correct, 'N') = 'Y' then 'Y' else 'N' end as is_correct,
                 coalesce(s.latitude, cp.latitude) as effective_latitude,
                 coalesce(s.longitude, cp.longitude) as effective_longitude
            from submissions s
            join checkpoints cp
              on cp.checkpoint_id = s.checkpoint_id
            join questions q
              on q.question_id = s.question_id
           where s.competition_id = p_competition_id
             and s.user_id = p_user_id
        )
        select b.checkpoint_title,
               b.submission_id,
               b.submitted_at,
               case
                 when lag(b.submitted_at) over (order by b.submitted_at asc, b.submission_id asc) is null then null
                 else round((cast(b.submitted_at as date) - cast(lag(b.submitted_at) over (order by b.submitted_at asc, b.submission_id asc) as date)) * 86400)
               end as delta_from_prev_seconds,
               b.awarded_points,
               b.answer_text,
               b.is_correct
          from base_rows b
         order by b.submitted_at desc, b.submission_id desc
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;

    o_total_elapsed_seconds := get_total_elapsed_seconds(
      p_competition_id => p_competition_id,
      p_user_id => p_user_id
    );
    o_distance_available := get_distance_available(
      p_competition_id => p_competition_id,
      p_user_id => p_user_id
    );
    o_total_distance_m := get_total_distance_m(
      p_competition_id => p_competition_id,
      p_user_id => p_user_id
    );
  end;

  -- get_submission_detail: Returns submission detail data.
  procedure get_submission_detail(
    p_competition_id in number,
    p_user_id in number,
    p_submission_id in number,
    p_requester_user_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_access_granted out varchar2,
    o_item_json out clob
  ) is
    l_question_id questions.question_id%type;
    l_question_type questions.question_type%type;
    l_selected_option_id submissions.selected_option_id%type;
    l_answer_text clob;
    l_lang varchar2(10);
    l_fallback_lang varchar2(10);
    l_is_organizer number := 0;
  begin
    select count(*)
      into l_is_organizer
      from competition_organizers co
     where co.competition_id = p_competition_id
       and co.user_id = p_requester_user_id
       and (co.end_date is null or co.end_date > sysdate);

    if l_is_organizer = 0 then
      o_access_granted := 'N';
      o_item_json := '{}';
      return;
    end if;
    o_access_granted := 'Y';

    l_lang := lower(nvl(trim(p_lang_code), 'et'));
    l_fallback_lang := lower(nvl(trim(p_default_lang_code), 'et'));
    if l_fallback_lang is null then
      l_fallback_lang := 'et';
    end if;
    if l_fallback_lang = l_lang then
      l_fallback_lang := null;
    end if;

    select s.question_id,
           q.question_type,
           s.selected_option_id,
           s.answer_text
      into l_question_id,
           l_question_type,
           l_selected_option_id,
           l_answer_text
      from submissions s
      join questions q
        on q.question_id = s.question_id
     where s.submission_id = p_submission_id
       and s.competition_id = p_competition_id
       and s.user_id = p_user_id;

    select json_object(
             'submission_id' value s.submission_id,
             'checkpoint_title' value cp.title,
             c_json_question_text value nvl(
               qt.question_text,
               nvl(
                 (
                   select qtf.question_text
                     from question_texts qtf
                    where qtf.question_id = q.question_id
                      and lower(qtf.lang_code) = l_fallback_lang
                      and qtf.start_date <= cast(s.submitted_at as date)
                      and (qtf.end_date is null or qtf.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 '---'
               )
             ),
             'question_type' value q.question_type, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             'points' value nvl(q.points, 0), -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             'wrong_points' value nvl(q.wrong_points, 0), -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             'submitted_at' value case
                when s.submitted_at is not null then to_char(s.submitted_at, pkg_common.c_iso_ts_format)
               else null
             end,
             'awarded_points' value nvl(s.awarded_points, 0),
             'competitor_answer' value case
               when q.question_type = 'SINGLE_CHOICE' then nvl(
                 (
                   select qot_et.option_text
                     from question_option_texts qot_et
                    where qot_et.option_id = s.selected_option_id
                      and lower(qot_et.lang_code) = l_lang
                      and qot_et.start_date <= cast(s.submitted_at as date)
                      and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 nvl(
                   (
                     select qot_en.option_text
                       from question_option_texts qot_en
                      where qot_en.option_id = s.selected_option_id
                        and lower(qot_en.lang_code) = l_fallback_lang
                        and qot_en.start_date <= cast(s.submitted_at as date)
                        and (qot_en.end_date is null or qot_en.end_date > cast(s.submitted_at as date))
                      fetch first 1 row only
                   ),
                   '---'
                 )
               )
               else dbms_lob.substr(s.answer_text, 4000, 1)
             end,
             'options' value case -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               when q.question_type = 'SINGLE_CHOICE' then (
                 select json_arrayagg(
                          json_object(
                            'option_text' value nvl( -- NOSONAR: S1192 repeated literal accepted for script readability/stability
                              (
                                select qot_et.option_text
                                  from question_option_texts qot_et
                                 where qot_et.option_id = qo.option_id
                                   and lower(qot_et.lang_code) = l_lang
                                   and qot_et.start_date <= cast(s.submitted_at as date)
                                   and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                                 fetch first 1 row only
                              ),
                              nvl(
                                (
                                  select qot_en.option_text
                                    from question_option_texts qot_en
                                   where qot_en.option_id = qo.option_id
                                     and lower(qot_en.lang_code) = l_fallback_lang
                                     and qot_en.start_date <= cast(s.submitted_at as date)
                                     and (qot_en.end_date is null or qot_en.end_date > cast(s.submitted_at as date))
                                   fetch first 1 row only
                                ),
                                '---'
                              )
                            ),
                            'is_correct' value case when qo.is_correct = 'Y' then 'Y' else 'N' end,
                            'is_selected' value case when qo.option_id = s.selected_option_id then 'Y' else 'N' end -- NOSONAR: S1192 repeated literal accepted for script readability/stability
                          ) returning clob
                        )
                   from question_options qo
                  where qo.question_id = q.question_id
                    and qo.start_date <= cast(s.submitted_at as date)
                    and (qo.end_date is null or qo.end_date > cast(s.submitted_at as date))
               )
               else (
                 select json_arrayagg(
                          json_object(
                            'option_text' value qa.answer_value,
                            'is_correct' value case when qa.is_correct = 'Y' then 'Y' else 'N' end,
                            'is_selected' value case
                              when qa.is_correct = 'Y'
                                   and pkg_submissions.normalize_text(qa.answer_value, qa.normalize_mode)
                                       = pkg_submissions.normalize_text(dbms_lob.substr(s.answer_text, 4000, 1), qa.normalize_mode)
                              then 'Y' else 'N'
                            end
                          ) returning clob
                        )
                   from question_answers qa
                  where qa.question_id = q.question_id
                    and qa.is_correct = 'Y'
                    and qa.start_date <= cast(s.submitted_at as date)
                    and (qa.end_date is null or qa.end_date > cast(s.submitted_at as date))
               )
             end
           returning clob
           )
      into o_item_json
      from submissions s
      join checkpoints cp
        on cp.checkpoint_id = s.checkpoint_id
      join questions q
        on q.question_id = s.question_id
      left join question_texts qt
        on qt.question_id = q.question_id
       and lower(qt.lang_code) = l_lang
       and qt.start_date <= cast(s.submitted_at as date)
       and (qt.end_date is null or qt.end_date > cast(s.submitted_at as date))
     where s.submission_id = p_submission_id
       and s.competition_id = p_competition_id
       and s.user_id = p_user_id;

    if o_item_json is null then
      o_item_json := '{}';
    end if;
  exception
    when no_data_found then
      o_item_json := '{}';
  end;

  -- get_checkpoint_results: Returns checkpoint results data.
  procedure get_checkpoint_results(
    p_competition_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  ) is
    l_is_organizer number := 0;
  begin
    select count(*)
      into l_is_organizer
      from competition_organizers co
     where co.competition_id = p_competition_id
       and co.user_id = p_requester_user_id
       and (co.end_date is null or co.end_date > sysdate);

    if l_is_organizer = 0 then
      o_access_granted := 'N';
      o_items_json := '[]';
      return;
    end if;
    o_access_granted := 'Y';

    select json_arrayagg(
             json_object(
               'checkpoint_id' value x.checkpoint_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'checkpoint_title' value x.checkpoint_title,
               'last_submission_at' value case
                  when x.last_submission_at is not null then to_char(x.last_submission_at, pkg_common.c_iso_ts_format)
                 else null
               end,
               'last_team' value x.last_team,
               'checkpoint_points' value x.checkpoint_points,
               'correct_count' value x.correct_count,
               'wrong_count' value x.wrong_count
             ) returning clob
           )
      into o_items_json
      from (
        with latest_alias as (
          select p.competition_id,
                 p.user_id,
                 p.alias_display,
                 row_number() over (
                   partition by p.competition_id, p.user_id
                   order by nvl(p.joined_at, timestamp '1900-01-01 00:00:00') desc,
                            p.competition_participant_id desc
                 ) as rn
            from competition_participants p
           where p.competition_id = p_competition_id
        ),
        last_sub as (
          select s.checkpoint_id,
                 s.user_id,
                 s.submitted_at,
                 row_number() over (
                   partition by s.checkpoint_id
                   order by s.submitted_at desc, s.submission_id desc
                 ) as rn
            from submissions s
           where s.competition_id = p_competition_id
        ),
        cp_points as (
          select q.checkpoint_id,
                 max(nvl(q.points, 0)) as checkpoint_points
            from questions q
           where (q.end_date is null or q.end_date > sysdate)
           group by q.checkpoint_id
        )
        select cp.checkpoint_id,
               cp.title as checkpoint_title,
               ls.submitted_at as last_submission_at,
               nvl(la.alias_display, to_char(ls.user_id)) as last_team,
               nvl(cpp.checkpoint_points, 0) as checkpoint_points,
               nvl(sum(case when s.is_correct = 'Y' then 1 else 0 end), 0) as correct_count,
               nvl(sum(case when s.is_correct = 'N' then 1 else 0 end), 0) as wrong_count
          from checkpoints cp
          left join submissions s
            on s.competition_id = p_competition_id
           and s.checkpoint_id = cp.checkpoint_id
          left join last_sub ls
            on ls.checkpoint_id = cp.checkpoint_id
           and ls.rn = 1
          left join latest_alias la
            on la.competition_id = p_competition_id
           and la.user_id = ls.user_id
           and la.rn = 1
          left join cp_points cpp
            on cpp.checkpoint_id = cp.checkpoint_id
         where cp.competition_id = p_competition_id
           and (cp.end_date is null or cp.end_date > sysdate)
         group by cp.checkpoint_id,
                  cp.title,
                  ls.submitted_at,
                  ls.user_id,
                  la.alias_display,
                  cpp.checkpoint_points
         order by lower(cp.title), cp.checkpoint_id
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- get_checkpoint_responders: Returns checkpoint responders data.
  procedure get_checkpoint_responders(
    p_competition_id in number,
    p_checkpoint_id in number,
    p_requester_user_id in number,
    o_access_granted out varchar2,
    o_items_json out clob
  ) is
    l_is_organizer number := 0;
  begin
    select count(*)
      into l_is_organizer
      from competition_organizers co
     where co.competition_id = p_competition_id
       and co.user_id = p_requester_user_id
       and (co.end_date is null or co.end_date > sysdate);

    if l_is_organizer = 0 then
      o_access_granted := 'N';
      o_items_json := '[]';
      return;
    end if;
    o_access_granted := 'Y';

    select json_arrayagg(
             json_object(
               'user_id' value x.user_id,
               'competitor_name' value x.competitor_name,
               'is_correct' value x.is_correct
             ) returning clob
           )
      into o_items_json
      from (
        with latest_alias as (
          select p.competition_id,
                 p.user_id,
                 p.alias_display,
                 row_number() over (
                   partition by p.competition_id, p.user_id
                   order by nvl(p.joined_at, timestamp '1900-01-01 00:00:00') desc,
                            p.competition_participant_id desc
                 ) as rn
            from competition_participants p
           where p.competition_id = p_competition_id
        ),
        latest_submission as (
          select s.user_id,
                 s.is_correct,
                 row_number() over (
                   partition by s.user_id
                   order by s.submitted_at desc, s.submission_id desc
                 ) as rn
            from submissions s
           where s.competition_id = p_competition_id
             and s.checkpoint_id = p_checkpoint_id
        )
        select ls.user_id,
               nvl(la.alias_display, to_char(ls.user_id)) as competitor_name,
               case when ls.is_correct = 'Y' then 'Y' else 'N' end as is_correct
          from latest_submission ls
          left join latest_alias la
            on la.competition_id = p_competition_id
           and la.user_id = ls.user_id
           and la.rn = 1
         where ls.rn = 1
         order by lower(nvl(la.alias_display, to_char(ls.user_id))), ls.user_id
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;
end pkg_results;
/

create or replace package pkg_competitor as
  -- get_session_by_participant_json: Returns a JSON object for the requested session by participant.
  procedure get_session_by_participant_json(
    p_user_id in number,
    p_competition_participant_id in number,
    o_item_json out clob
  );

  -- join_preview_json: Performs this business operation according to package rules.
  procedure join_preview_json(
    p_user_id in number,
    p_access_code in varchar2,
    p_lang_code in varchar2,
    p_alias_display in varchar2,
    o_item_json out clob
  );

  -- join_by_code: Performs this business operation according to package rules.
  procedure join_by_code(
    p_user_id in number,
    p_access_code in varchar2,
    p_alias_display in varchar2,
    p_contact_email in varchar2,
    p_terms_id in number,
    p_terms_lang_code in varchar2,
    p_accept_terms in varchar2,
    p_current_competition_participant_id in number,
    o_user_id out number,
    o_competition_id out number,
    o_competition_participant_id out number,
    o_switched_from_participant_id out number,
    o_no_change out varchar2
  );

  -- list_my_competitions_json: Returns a JSON array for the requested my competitions.
  procedure list_my_competitions_json(
    p_user_id in number,
    o_items_json out clob
  );
  -- get_terms_for_competition_json: Returns a JSON object for the requested terms for competition.
  procedure get_terms_for_competition_json(
    p_user_id in number,
    p_competition_id in number,
    p_lang_code in varchar2,
    o_item_json out clob
  );

  -- list_open_checkpoints_json: Returns a JSON array for the requested open checkpoints.
  procedure list_open_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_items_json out clob
  );

  -- list_map_checkpoints_json: Returns a JSON array for the requested map checkpoints.
  procedure list_map_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob,
    o_declination out number,
    o_declination_last_updated out varchar2
  );
  -- get_progress_json: Returns a JSON object for the requested progress.
  procedure get_progress_json(
    p_user_id in number,
    p_competition_id in number,
    o_progress_json out clob
  );

  -- list_my_submissions_json: Returns a JSON array for the requested my submissions.
  procedure list_my_submissions_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob
  );

  -- get_my_submission_detail_json: Returns a JSON object for the requested my submission detail.
  procedure get_my_submission_detail_json(
    p_user_id in number,
    p_competition_id in number,
    p_submission_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_item_json out clob
  );
end pkg_competitor;
/

create or replace package body pkg_competitor as
  c_json_question_text constant varchar2(30) := 'question_text';

  -- get_session_by_participant_json: Returns a JSON object for the requested session by participant.
  procedure get_session_by_participant_json(
    p_user_id in number,
    p_competition_participant_id in number,
    o_item_json out clob
  ) is
  begin
    o_item_json := null;
    if p_user_id is null or p_competition_participant_id is null then
      return;
    end if;

    begin
      select json_object(
               'competition_participant_id' value cp.competition_participant_id,
               'competition_id' value c.competition_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'competition_name' value c.name,
               'competition_description' value c.description,
               'competition_type' value pkg_common.normalize_competition_type(c.type),
               'alias_display' value cp.alias_display,
               'competitor_name' value nvl(nullif(trim(cp.alias_display), ''), nvl(nullif(trim(u.full_name), ''), '---')),
               'use_location' value nvl(c.use_location, 'N'), -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'show_competitor_location' value nvl(c.show_competitor_location, 'Y') -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             )
        into o_item_json
        from competition_participants cp
        join competitions c
          on c.competition_id = cp.competition_id
        left join users u
          on u.user_id = cp.user_id
       where cp.competition_participant_id = p_competition_participant_id
         and cp.user_id = p_user_id
         and cp.end_date is null
         and (c.end_date is null or c.end_date > sysdate)
         and c.status in ('INACTIVE', 'ACTIVE') -- NOSONAR: S1192 repeated literal accepted for script readability/stability
       fetch first 1 row only;
    exception
      when no_data_found then
        o_item_json := null;
    end;
  end;

  -- join_preview_json: Performs this business operation according to package rules.
  procedure join_preview_json(
    p_user_id in number,
    p_access_code in varchar2,
    p_lang_code in varchar2,
    p_alias_display in varchar2,
    o_item_json out clob
  ) is
    l_competition_id number;
    l_access_code_id number;
    l_max_uses number;
    l_used_count number;
    l_terms_id number;
    l_terms_lang_code varchar2(10);
    l_terms_text clob;
    l_already_active varchar2(1) := 'N';
    l_now_utc_ts timestamp;
    l_lang_code varchar2(10);
  begin
    o_item_json := null;
    l_now_utc_ts := cast((systimestamp at time zone 'UTC') as timestamp);
    l_lang_code := lower(nvl(trim(p_lang_code), 'et'));

    if p_access_code is null then
      raise_application_error(-20030, 'access_code is required');
    end if;
    if p_alias_display is not null and trim(p_alias_display) is null then
      raise_application_error(-20101, 'alias is required');
    end if;

    begin
      select c.access_code_id,
             c.competition_id,
             c.max_uses,
             c.used_count
        into l_access_code_id, l_competition_id, l_max_uses, l_used_count
        from competition_access_codes c
        join competitions comp on comp.competition_id = c.competition_id
       where c.code = p_access_code
         and c.code_type = 'COMPETITOR'
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > l_now_utc_ts)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and comp.status in ('INACTIVE', 'ACTIVE')
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20031, 'invalid or inactive access code');
    end;

    if l_max_uses is not null and l_used_count >= l_max_uses then
      raise_application_error(-20032, 'access code usage limit reached');
    end if;

    begin
      select t.terms_id
        into l_terms_id
        from competition_terms t
       where t.competition_id = l_competition_id
         and t.status = 'ACTIVE'
         and (t.end_date is null or t.end_date > sysdate)
       order by t.version_no desc, t.terms_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20120, 'no active terms for competition');
    end;

    begin
      select lower(tt.lang_code), tt.terms_text
        into l_terms_lang_code, l_terms_text
        from competition_terms_texts tt
       where tt.terms_id = l_terms_id
         and lower(tt.lang_code) = l_lang_code
         and (tt.end_date is null or tt.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        begin
          select lower(tt.lang_code), tt.terms_text
            into l_terms_lang_code, l_terms_text
            from competition_terms_texts tt
           where tt.terms_id = l_terms_id
             and lower(tt.lang_code) = 'et'
             and (tt.end_date is null or tt.end_date > sysdate)
           fetch first 1 row only;
        exception
          when no_data_found then
            begin
              select lower(tt.lang_code), tt.terms_text
                into l_terms_lang_code, l_terms_text
                from competition_terms_texts tt
               where tt.terms_id = l_terms_id
                 and (tt.end_date is null or tt.end_date > sysdate)
               order by tt.lang_code
               fetch first 1 row only;
            exception
              when no_data_found then
                return;
            end;
        end;
    end;

    if p_user_id is not null then
      begin
        select 'Y'
          into l_already_active
          from competition_participants cp
         where cp.competition_id = l_competition_id
           and cp.user_id = p_user_id
           and cp.end_date is null
         fetch first 1 row only;
      exception
        when no_data_found then
          l_already_active := 'N';
      end;
    else
      l_already_active := 'N';
    end if;

    if l_already_active = 'Y' then
      raise_application_error(-20131, 'user is already active participant for this competition'); -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    end if;

    if p_alias_display is not null and trim(p_alias_display) is not null then
      begin
        select 1
          into l_used_count
          from competition_participants cp
         where cp.competition_id = l_competition_id
           and cp.end_date is null
           and nlssort(trim(cp.alias_display), 'NLS_SORT=BINARY_CI') = -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               nlssort(trim(p_alias_display), 'NLS_SORT=BINARY_CI')
         fetch first 1 row only;
        raise_application_error(-20130, 'alias already exists in this competition');
      exception
        when no_data_found then
          null;
      end;
    end if;

    select json_object(
             'competition_id' value c.competition_id,
             'competition_name' value c.name,
             'competition_description' value c.description,
             'already_active_for_user' value l_already_active,
             'terms' value json_object( -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'terms_id' value l_terms_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'lang_code' value l_terms_lang_code, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'terms_text' value l_terms_text -- NOSONAR: S1192 repeated literal accepted for script readability/stability
             )
             returning clob
           )
      into o_item_json
      from competitions c
     where c.competition_id = l_competition_id;
  end;

  -- join_by_code: Performs this business operation according to package rules.
  procedure join_by_code(
    p_user_id in number,
    p_access_code in varchar2,
    p_alias_display in varchar2,
    p_contact_email in varchar2,
    p_terms_id in number,
    p_terms_lang_code in varchar2,
    p_accept_terms in varchar2,
    p_current_competition_participant_id in number,
    o_user_id out number,
    o_competition_id out number,
    o_competition_participant_id out number,
    o_switched_from_participant_id out number,
    o_no_change out varchar2
  ) is
    l_access_code_id number;
    l_max_uses number;
    l_used_count number;
    l_terms_id number;
    l_current_competition_id number;
    l_existing_participant_id number;
    l_effective_user_id number;
    l_now_utc_ts timestamp;
    l_alias_dummy number;
  begin
    l_now_utc_ts := cast((systimestamp at time zone 'UTC') as timestamp);
    o_switched_from_participant_id := null;
    o_no_change := 'N';
    o_competition_participant_id := null;
    o_user_id := null;

    if p_access_code is null then
      raise_application_error(-20030, 'access_code is required');
    end if;
    if trim(p_alias_display) is null then
      raise_application_error(-20101, 'alias is required');
    end if;
    if nvl(upper(p_accept_terms), 'N') <> 'Y' then
      raise_application_error(-20102, 'terms acceptance is required');
    end if;

    if p_user_id is null then
      l_effective_user_id := seq_users.nextval;
      insert into users (
        user_id, auth_type, start_date, created_at
      ) values (
        l_effective_user_id, 'ANON', trunc(sysdate), systimestamp
      );
    else
      l_effective_user_id := p_user_id;
    end if;
    o_user_id := l_effective_user_id;

    begin
      select c.access_code_id,
             c.competition_id,
             c.max_uses,
             c.used_count
        into l_access_code_id, o_competition_id, l_max_uses, l_used_count
        from competition_access_codes c
        join competitions comp on comp.competition_id = c.competition_id
       where c.code = p_access_code
         and c.code_type = 'COMPETITOR'
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > l_now_utc_ts)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and comp.status in ('INACTIVE', 'ACTIVE')
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20031, 'invalid or inactive access code');
    end;

    if l_max_uses is not null and l_used_count >= l_max_uses then
      raise_application_error(-20032, 'access code usage limit reached');
    end if;

    begin
      select t.terms_id
        into l_terms_id
        from competition_terms t
       where t.competition_id = o_competition_id
         and t.status = 'ACTIVE'
         and (t.end_date is null or t.end_date > sysdate)
       order by t.version_no desc, t.terms_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20120, 'no active terms for competition');
    end;
    if l_terms_id != p_terms_id then
      raise_application_error(-20103, 'terms version mismatch');
    end if;

    begin
      select cp.competition_participant_id, cp.competition_id
        into l_existing_participant_id, l_current_competition_id
        from competition_participants cp
       where cp.competition_participant_id = p_current_competition_participant_id
          and cp.user_id = l_effective_user_id
         and cp.end_date is null
       fetch first 1 row only;
    exception
      when no_data_found then
        l_existing_participant_id := null;
        l_current_competition_id := null;
    end;

    if l_current_competition_id = o_competition_id and l_existing_participant_id is not null then
      raise_application_error(-20131, 'user is already active participant for this competition');
    end if;

    begin
      select cp.competition_participant_id
        into o_competition_participant_id
        from competition_participants cp
       where cp.competition_id = o_competition_id
          and cp.user_id = l_effective_user_id
         and cp.end_date is null
       fetch first 1 row only;
      raise_application_error(-20131, 'user is already active participant for this competition');
    exception
      when no_data_found then
        null;
    end;

    begin
      select 1
        into l_alias_dummy
        from competition_participants cp
       where cp.competition_id = o_competition_id
         and cp.end_date is null
         and nlssort(trim(cp.alias_display), 'NLS_SORT=BINARY_CI') =
             nlssort(trim(p_alias_display), 'NLS_SORT=BINARY_CI')
       fetch first 1 row only;
      raise_application_error(-20130, 'alias already exists in this competition');
    exception
      when no_data_found then
        null;
    end;

    insert into competition_participants (
      competition_participant_id,
      competition_id,
      user_id,
      access_code_id,
      alias_display,
      contact_email,
      terms_id,
      terms_lang_code,
      terms_accepted_at,
      status,
      start_date,
      joined_at
    ) values (
      seq_competition_participants.nextval,
      o_competition_id,
      l_effective_user_id,
      l_access_code_id,
      trim(p_alias_display),
      case when trim(p_contact_email) is not null then trim(p_contact_email) else null end,
      l_terms_id,
      lower(trim(p_terms_lang_code)),
      systimestamp,
      'ACTIVE',
      trunc(sysdate),
      systimestamp
    ) returning competition_participant_id into o_competition_participant_id;

    if l_existing_participant_id is not null then
      update competition_participants cp
         set cp.end_date = trunc(sysdate),
             cp.status = case when cp.status = 'ACTIVE' then 'ENDED_SWITCHED' else cp.status end
       where cp.competition_participant_id = l_existing_participant_id
         and cp.end_date is null;
      o_switched_from_participant_id := l_existing_participant_id;
    end if;

    update competition_access_codes
       set used_count = used_count + 1
     where access_code_id = l_access_code_id;
  end;

  -- get_terms_for_competition_json: Returns a JSON object for the requested terms for competition.
  procedure get_terms_for_competition_json(
    p_user_id in number,
    p_competition_id in number,
    p_lang_code in varchar2,
    o_item_json out clob
  ) is
    l_terms_id number;
    l_terms_lang_code varchar2(10);
    l_terms_text clob;
    l_lang_code varchar2(10);
    l_cp_terms_id number;
    l_cp_terms_lang_code varchar2(10);
  begin
    o_item_json := null;
    l_lang_code := lower(nvl(trim(p_lang_code), 'et'));
    if p_user_id is null or p_competition_id is null then
      return;
    end if;

    begin
      select cp.terms_id,
             lower(trim(cp.terms_lang_code))
        into l_cp_terms_id,
             l_cp_terms_lang_code
        from competition_participants cp
       where cp.user_id = p_user_id
         and cp.competition_id = p_competition_id
         and cp.end_date is null
       fetch first 1 row only;
    exception
      when no_data_found then
        return;
    end;

    l_terms_id := l_cp_terms_id;
    if l_terms_id is null then
      begin
        select t.terms_id
          into l_terms_id
          from competition_terms t
         where t.competition_id = p_competition_id
           and t.status = 'ACTIVE'
           and (t.end_date is null or t.end_date > sysdate)
         order by t.version_no desc, t.terms_id desc
         fetch first 1 row only;
      exception
        when no_data_found then
          return;
      end;
    end if;

    begin
      select lower(tt.lang_code), tt.terms_text
        into l_terms_lang_code, l_terms_text
        from competition_terms_texts tt
       where tt.terms_id = l_terms_id
         and lower(tt.lang_code) = l_lang_code
         and (tt.end_date is null or tt.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        begin
          select lower(tt.lang_code), tt.terms_text
            into l_terms_lang_code, l_terms_text
            from competition_terms_texts tt
           where tt.terms_id = l_terms_id
             and lower(tt.lang_code) = nvl(l_cp_terms_lang_code, 'et')
             and (tt.end_date is null or tt.end_date > sysdate)
           fetch first 1 row only;
        exception
          when no_data_found then
            select lower(tt.lang_code), tt.terms_text
              into l_terms_lang_code, l_terms_text
              from competition_terms_texts tt
             where tt.terms_id = l_terms_id
               and (tt.end_date is null or tt.end_date > sysdate)
             order by tt.lang_code
             fetch first 1 row only;
        end;
    end;

    select json_object(
             'competition_id' value p_competition_id,
             'terms' value json_object(
               'terms_id' value l_terms_id,
               'lang_code' value l_terms_lang_code,
               'terms_text' value l_terms_text
             )
             returning clob
           )
      into o_item_json
      from dual;
  end;

  -- list_my_competitions_json: Returns a JSON array for the requested my competitions.
  procedure list_my_competitions_json(
    p_user_id in number,
    o_items_json out clob
  ) is
    l_now_utc_ts timestamp;
  begin
    l_now_utc_ts := cast((systimestamp at time zone 'UTC') as timestamp);

    select json_arrayagg(
             json_object(
               'competition_id' value x.competition_id,
               'name' value x.name,
               'description' value x.description, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'type' value x.type,
                'starts_at' value case when x.starts_at is not null then to_char(x.starts_at, pkg_common.c_iso_ts_format) else null end,
                'ends_at' value case when x.ends_at is not null then to_char(x.ends_at, pkg_common.c_iso_ts_format) else null end,
               'use_location' value nvl(x.use_location, 'N'),
               'show_competitor_location' value nvl(x.show_competitor_location, 'Y')
             ) returning clob
           )
      into o_items_json
      from (
        select c.competition_id,
               c.name,
               c.description,
               nvl(c.type, 'R') as type,
               c.starts_at,
               c.ends_at,
               c.use_location,
               c.show_competitor_location
         from competition_participants cp
          join competitions c
            on c.competition_id = cp.competition_id
         where cp.user_id = p_user_id
           and (cp.end_date is null or cp.end_date > sysdate)
           and (c.end_date is null or c.end_date > sysdate)
           and c.status = 'ACTIVE'
           and (c.starts_at is null or c.starts_at <= l_now_utc_ts)
           and (c.ends_at is null or c.ends_at > l_now_utc_ts)
         order by nvl(c.starts_at, timestamp '1900-01-01 00:00:00'), c.competition_id
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- list_open_checkpoints_json: Returns a JSON array for the requested open checkpoints.
  procedure list_open_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_items_json out clob
  ) is
    l_use_location varchar2(1) := 'N';
    l_comp_radius number;
    l_comp_type varchar2(1) := pkg_common.c_competition_type_random;
    l_start_exists number := 0;
    l_start_answered number := 0;
    l_finish_answered number := 0;
    l_next_ordered_checkpoint_id checkpoints.checkpoint_id%type;
  begin
    begin
      select nvl(c.use_location, 'N'), c.radius_m, pkg_common.normalize_competition_type(c.type)
        into l_use_location, l_comp_radius, l_comp_type
        from competitions c
       where c.competition_id = p_competition_id
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        l_use_location := 'N';
        l_comp_radius := null;
    end;

    select count(*)
      into l_finish_answered
      from submissions s
      join checkpoints cp
        on cp.checkpoint_id = s.checkpoint_id
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id
       and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_finish
       and (cp.end_date is null or cp.end_date > sysdate);

    if l_finish_answered > 0 then
      o_items_json := '[]';
      return;
    end if;

    select count(*)
      into l_start_exists
      from checkpoints cp
     where cp.competition_id = p_competition_id
       and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
       and (cp.end_date is null or cp.end_date > sysdate);

    if l_start_exists > 0 then
      select count(*)
        into l_start_answered
        from submissions s
        join checkpoints cp
          on cp.checkpoint_id = s.checkpoint_id
       where s.competition_id = p_competition_id
         and s.user_id = p_user_id
         and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
         and (cp.end_date is null or cp.end_date > sysdate);
    end if;

    if l_comp_type = pkg_common.c_competition_type_sequential then
      l_next_ordered_checkpoint_id := pkg_common.get_next_ordered_checkpoint_id(
        p_user_id => p_user_id,
        p_competition_id => p_competition_id
      );
    end if;

    select json_arrayagg(
             json_object(
               'checkpoint_id' value z.checkpoint_id,
               'checkpoint_title' value z.checkpoint_title,
               'checkpoint_order_no' value z.checkpoint_order_no,
               'checkpoint_type' value z.checkpoint_type, -- NOSONAR: repeated JSON key is intentional for payload readability
               'competition_type' value z.competition_type,
               'question_id' value z.question_id, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'question_type' value z.question_type,
               'points' value z.points,
               'text_et' value z.text_et, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'text_en' value z.text_en, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'input_type' value z.input_type,
               'input_max_length' value z.input_max_length,
               'latitude' value z.latitude, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'longitude' value z.longitude, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'radius_m' value z.radius_m, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'location_required' value z.location_required, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
               'options' value nvl(z.options_json, '[]') format json
             )
             order by z.sort_location_group, z.sort_distance_m, z.sort_title
             returning clob
           )
      into o_items_json
      from (
        select cp.checkpoint_id,
               cp.title as checkpoint_title,
               cp.order_no as checkpoint_order_no,
               pkg_common.normalize_checkpoint_type(cp.checkpoint_type) as checkpoint_type,
               l_comp_type as competition_type,
               q.question_id,
               q.question_type,
               q.points,
               q.input_type,
               q.input_max_length,
               cp.latitude,
               cp.longitude,
               cp.radius_m,
               cp.location_required,
               case when nvl(cp.location_required, 'N') = 'Y' then 0 else 1 end as sort_location_group,
               lower(cp.title) as sort_title,
               case
                 when p_latitude is not null
                  and p_longitude is not null
                  and cp.latitude is not null
                  and cp.longitude is not null
                 then
                   6371000 * 2 * asin(
                     sqrt(
                       power(sin((cp.latitude - p_latitude) * 0.008726646259971648 / 2), 2) +
                       cos(p_latitude * 0.017453292519943295) *
                       cos(cp.latitude * 0.017453292519943295) *
                       power(sin((cp.longitude - p_longitude) * 0.008726646259971648 / 2), 2)
                     )
                   )
                 else null
               end as distance_m,
               case
                 when nvl(cp.location_required, 'N') = 'Y'
                 then nvl(
                   case
                     when p_latitude is not null
                      and p_longitude is not null
                      and cp.latitude is not null
                      and cp.longitude is not null
                     then
                       6371000 * 2 * asin(
                         sqrt(
                           power(sin((cp.latitude - p_latitude) * 0.008726646259971648 / 2), 2) +
                           cos(p_latitude * 0.017453292519943295) *
                           cos(cp.latitude * 0.017453292519943295) *
                           power(sin((cp.longitude - p_longitude) * 0.008726646259971648 / 2), 2)
                         )
                       )
                     else null
                   end,
                   999999999
                 )
                 else 999999999
               end as sort_distance_m,
               max(case when lower(qt.lang_code) = 'et' then qt.question_text end) as text_et,
               max(case when lower(qt.lang_code) = 'en' then qt.question_text end) as text_en,
               (
                 select json_arrayagg(
                          json_object(
                            'option_id' value qo.option_id,
                            'option_code' value qo.option_code, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
                            'text_et' value (
                              select max(case when lower(qot.lang_code) = 'et' then qot.option_text end)
                                from question_option_texts qot
                               where qot.option_id = qo.option_id
                                 and (qot.end_date is null or qot.end_date > sysdate)
                            ),
                            'text_en' value (
                              select max(case when lower(qot.lang_code) = 'en' then qot.option_text end)
                                from question_option_texts qot
                               where qot.option_id = qo.option_id
                                 and (qot.end_date is null or qot.end_date > sysdate)
                            )
                          ) returning clob
                        )
                   from question_options qo
                  where qo.question_id = q.question_id
                    and (qo.end_date is null or qo.end_date > sysdate)
               ) as options_json
          from checkpoints cp
          join questions q
            on q.checkpoint_id = cp.checkpoint_id
          left join question_texts qt
            on qt.question_id = q.question_id
           and (qt.end_date is null or qt.end_date > sysdate)
         where cp.competition_id = p_competition_id
           and (cp.end_date is null or cp.end_date > sysdate)
           and (q.end_date is null or q.end_date > sysdate)
           and (
             l_start_exists = 0
             or l_start_answered > 0
             or pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
           )
           and (
             l_comp_type <> pkg_common.c_competition_type_sequential
             or (
               l_start_exists > 0
               and l_start_answered = 0
               and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_start
             )
             or (
               l_next_ordered_checkpoint_id is not null
               and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_normal
               and cp.checkpoint_id = l_next_ordered_checkpoint_id
             )
             or (
               l_next_ordered_checkpoint_id is null
               and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = pkg_common.c_checkpoint_type_finish
             )
           )
           and (
             l_use_location <> 'Y'
             or nvl(cp.location_required, 'N') = 'N'
             or (
               p_latitude is not null
               and p_longitude is not null
               and cp.latitude is not null
               and cp.longitude is not null
               and (
                 6371000 * 2 * asin(
                   sqrt(
                     power(sin((cp.latitude - p_latitude) * 0.008726646259971648 / 2), 2) +
                     cos(p_latitude * 0.017453292519943295) *
                     cos(cp.latitude * 0.017453292519943295) *
                     power(sin((cp.longitude - p_longitude) * 0.008726646259971648 / 2), 2)
                   )
                 )
               ) <= nvl(cp.radius_m, l_comp_radius)
             )
           )
           and not exists (
             select 1
              from submissions s
             where s.competition_id = p_competition_id
               and s.user_id = p_user_id
               and s.checkpoint_id = cp.checkpoint_id
               and s.question_id = q.question_id
           )
         group by cp.checkpoint_id, cp.title, cp.checkpoint_type, cp.order_no, q.question_id, q.question_type, q.points, q.input_type, q.input_max_length,
                  cp.latitude, cp.longitude, cp.radius_m, cp.location_required
      ) z;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- list_map_checkpoints_json: Returns a JSON array for the requested map checkpoints.
  procedure list_map_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob,
    o_declination out number,
    o_declination_last_updated out varchar2
  ) is
  begin
    select
      (select json_arrayagg(
                json_object(
                  'checkpoint_id' value x.checkpoint_id,
                  'checkpoint_title' value x.checkpoint_title,
                  'checkpoint_order_no' value x.checkpoint_order_no,
                  'checkpoint_type' value x.checkpoint_type,
                  'competition_type' value x.competition_type,
                  'question_id' value x.question_id,
                  'points' value x.points,
                  'latitude' value x.latitude,
                  'longitude' value x.longitude,
                  'radius_m' value x.radius_m,
                  'location_required' value x.location_required,
                  'is_answered' value x.is_answered
                )
                order by lower(x.checkpoint_title), x.checkpoint_id
                returning clob
              )
         from (
           select cp.checkpoint_id,
                  cp.title as checkpoint_title,
                  cp.order_no as checkpoint_order_no,
                  pkg_common.normalize_checkpoint_type(cp.checkpoint_type) as checkpoint_type,
                  nvl(c.type, 'R') as competition_type,
                  q.question_id,
                  q.points,
                  cp.latitude,
                  cp.longitude,
                  case
                    when nvl(cp.location_required, 'N') = 'Y' then coalesce(cp.radius_m, c.radius_m, 0)
                    else cp.radius_m
                  end as radius_m,
                  nvl(cp.location_required, 'N') as location_required,
                  case
                    when exists (
                      select 1
                        from submissions s
                       where s.competition_id = p_competition_id
                         and s.user_id = p_user_id
                         and s.checkpoint_id = cp.checkpoint_id
                         and s.question_id = q.question_id
                    ) then 'Y'
                    else 'N'
                  end as is_answered
             from checkpoints cp
             join competitions c
               on c.competition_id = cp.competition_id
             join questions q
               on q.checkpoint_id = cp.checkpoint_id
            where cp.competition_id = p_competition_id
              and (cp.end_date is null or cp.end_date > sysdate)
              and (q.end_date is null or q.end_date > sysdate)
              and cp.latitude is not null
              and cp.longitude is not null
         ) x),
      nvl((select cd.declination from competition_declinations cd where cd.competition_id = p_competition_id), 0),
      (select to_char(cd.last_updated, pkg_common.c_iso_ts_format) from competition_declinations cd where cd.competition_id = p_competition_id)
      into o_items_json,
           o_declination,
           o_declination_last_updated
      from dual;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- get_progress_json: Returns a JSON object for the requested progress.
  procedure get_progress_json(
    p_user_id in number,
    p_competition_id in number,
    o_progress_json out clob
  ) is
    l_total number := 0;
    l_answered number := 0;
    l_score number := 0;
  begin
    select count(distinct cp.checkpoint_id)
      into l_total
      from checkpoints cp
      join questions q
        on q.checkpoint_id = cp.checkpoint_id
     where cp.competition_id = p_competition_id
       and (cp.end_date is null or cp.end_date > sysdate)
       and (q.end_date is null or q.end_date > sysdate);

    select count(distinct cp.checkpoint_id)
      into l_answered
      from submissions s
      join questions q
        on q.question_id = s.question_id
      join checkpoints cp
        on cp.checkpoint_id = q.checkpoint_id
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id
       and cp.competition_id = p_competition_id
       and (cp.end_date is null or cp.end_date > sysdate)
       and (q.end_date is null or q.end_date > sysdate);

    pkg_results.get_competition_score(
      p_competition_id => p_competition_id,
      p_user_id        => p_user_id,
      o_score          => l_score
    );

    select json_object(
             'total_checkpoints' value nvl(l_total, 0),
             'answered_checkpoints' value nvl(l_answered, 0),
             'score' value nvl(l_score, 0)
             returning clob
           )
      into o_progress_json
      from dual;
  end;

  -- list_my_submissions_json: Returns a JSON array for the requested my submissions.
  procedure list_my_submissions_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'checkpoint_title' value x.checkpoint_title,
               'submission_id' value x.submission_id,
               'submitted_at' value case
                  when x.submitted_at is not null then to_char(x.submitted_at, pkg_common.c_iso_ts_format)
                 else null
               end,
               'awarded_points' value x.awarded_points
             ) returning clob
           )
      into o_items_json
      from (
        select cp.title as checkpoint_title,
               s.submission_id,
               s.submitted_at,
               nvl(s.awarded_points, 0) as awarded_points
          from submissions s
          join checkpoints cp
            on cp.checkpoint_id = s.checkpoint_id
          join questions q
            on q.question_id = s.question_id
         where s.user_id = p_user_id
           and s.competition_id = p_competition_id
           and (cp.end_date is null or cp.end_date > sysdate)
           and (q.end_date is null or q.end_date > sysdate)
         order by s.submitted_at desc, s.submission_id desc
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- get_my_submission_detail_json: Returns a JSON object for the requested my submission detail.
  procedure get_my_submission_detail_json(
    p_user_id in number,
    p_competition_id in number,
    p_submission_id in number,
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_item_json out clob
  ) is
    l_lang varchar2(10);
    l_fallback_lang varchar2(10);
  begin
    l_lang := lower(nvl(trim(p_lang_code), 'et'));
    l_fallback_lang := lower(nvl(trim(p_default_lang_code), 'et'));
    if l_fallback_lang is null then
      l_fallback_lang := 'et';
    end if;
    if l_fallback_lang = l_lang then
      l_fallback_lang := null;
    end if;

    select json_object(
             'submission_id' value s.submission_id,
             'checkpoint_title' value cp.title,
             c_json_question_text value nvl(
               qt.question_text,
               nvl(
                 (
                   select qtf.question_text
                     from question_texts qtf
                    where qtf.question_id = q.question_id
                      and lower(qtf.lang_code) = l_fallback_lang
                      and qtf.start_date <= cast(s.submitted_at as date)
                      and (qtf.end_date is null or qtf.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 '---'
               )
             ),
             'question_type' value q.question_type,
             'points' value nvl(q.points, 0),
             'wrong_points' value nvl(q.wrong_points, 0),
             'submitted_at' value case
                when s.submitted_at is not null then to_char(s.submitted_at, pkg_common.c_iso_ts_format)
               else null
             end,
             'awarded_points' value nvl(s.awarded_points, 0),
             'competitor_answer' value case
               when q.question_type = 'SINGLE_CHOICE' then nvl(
                 (
                   select qot_et.option_text
                     from question_option_texts qot_et
                    where qot_et.option_id = s.selected_option_id
                      and lower(qot_et.lang_code) = l_lang
                      and qot_et.start_date <= cast(s.submitted_at as date)
                      and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 nvl(
                   (
                     select qot_en.option_text
                       from question_option_texts qot_en
                      where qot_en.option_id = s.selected_option_id
                        and lower(qot_en.lang_code) = l_fallback_lang
                        and qot_en.start_date <= cast(s.submitted_at as date)
                        and (qot_en.end_date is null or qot_en.end_date > cast(s.submitted_at as date))
                      fetch first 1 row only
                   ),
                   (
                     select qo.option_code
                       from question_options qo
                      where qo.option_id = s.selected_option_id
                        and qo.start_date <= cast(s.submitted_at as date)
                        and (qo.end_date is null or qo.end_date > cast(s.submitted_at as date))
                      fetch first 1 row only
                   )
                 )
               )
               else dbms_lob.substr(s.answer_text, 4000, 1)
             end,
             'responders_count' value (
               select count(distinct sx.user_id)
                 from submissions sx
                where sx.competition_id = s.competition_id
                  and sx.checkpoint_id = s.checkpoint_id
                  and sx.question_id = s.question_id
             ),
             'correct_pct' value (
               select round(
                        100 * sum(case when sx.is_correct = 'Y' then 1 else 0 end) /
                        nullif(count(distinct sx.user_id), 0),
                        1
                      )
                 from submissions sx
                where sx.competition_id = s.competition_id
                  and sx.checkpoint_id = s.checkpoint_id
                  and sx.question_id = s.question_id
             ),
             'options' value case
               when q.question_type = 'SINGLE_CHOICE' then (
                 select json_arrayagg(
                          json_object(
                            'option_text' value nvl(
                              (
                                select qot_et.option_text
                                  from question_option_texts qot_et
                                 where qot_et.option_id = qo.option_id
                                   and lower(qot_et.lang_code) = l_lang
                                   and qot_et.start_date <= cast(s.submitted_at as date)
                                   and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                                 fetch first 1 row only
                              ),
                              nvl(
                                (
                                  select qot_en.option_text
                                    from question_option_texts qot_en
                                   where qot_en.option_id = qo.option_id
                                     and lower(qot_en.lang_code) = l_fallback_lang
                                     and qot_en.start_date <= cast(s.submitted_at as date)
                                     and (qot_en.end_date is null or qot_en.end_date > cast(s.submitted_at as date))
                                   fetch first 1 row only
                                ),
                                qo.option_code
                              )
                            ),
                            'is_correct' value case when qo.is_correct = 'Y' then 'Y' else 'N' end,
                            'is_selected' value case when qo.option_id = s.selected_option_id then 'Y' else 'N' end
                          ) returning clob
                        )
                   from question_options qo
                  where qo.question_id = q.question_id
                    and qo.start_date <= cast(s.submitted_at as date)
                    and (qo.end_date is null or qo.end_date > cast(s.submitted_at as date))
               )
               else (
                 select json_arrayagg(
                          json_object(
                            'option_text' value qa.answer_value,
                            'is_correct' value case when qa.is_correct = 'Y' then 'Y' else 'N' end,
                            'is_selected' value case
                              when qa.is_correct = 'Y'
                                   and pkg_submissions.normalize_text(qa.answer_value, qa.normalize_mode)
                                       = pkg_submissions.normalize_text(dbms_lob.substr(s.answer_text, 4000, 1), qa.normalize_mode)
                              then 'Y' else 'N'
                            end
                          ) returning clob
                        )
                   from question_answers qa
                  where qa.question_id = q.question_id
                    and qa.is_correct = 'Y'
                    and qa.start_date <= cast(s.submitted_at as date)
                    and (qa.end_date is null or qa.end_date > cast(s.submitted_at as date))
               )
             end
             returning clob
           )
      into o_item_json
      from submissions s
      join checkpoints cp
        on cp.checkpoint_id = s.checkpoint_id
      join questions q
        on q.question_id = s.question_id
      left join question_texts qt
        on qt.question_id = q.question_id
       and lower(qt.lang_code) = l_lang
       and qt.start_date <= cast(s.submitted_at as date)
       and (qt.end_date is null or qt.end_date > cast(s.submitted_at as date))
     where s.user_id = p_user_id
       and s.competition_id = p_competition_id
       and s.submission_id = p_submission_id;

    if o_item_json is null then
      o_item_json := '{}';
    end if;
  exception
    when no_data_found then
      o_item_json := '{}';
  end;
end pkg_competitor;
/

create or replace package pkg_admin_content as
  -- list_competitions_json: Returns a JSON array for the requested competitions.
  procedure list_competitions_json(p_user_id in number, o_items_json out clob);
  -- list_all_competitions_json: Returns a JSON array for the requested all competitions.
  procedure list_all_competitions_json(o_items_json out clob);
  -- create_empty_competition: Creates a new empty competition record.
  procedure create_empty_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  );
  -- copy_competition: Copies data from source entities according to provided flags.
  procedure copy_competition(
    p_source_competition_id in number,
    p_copy_questions in varchar2,
    p_copy_organizers in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  );
  -- remove_competition_organizer: Removes the requested relation or assignment.
  procedure remove_competition_organizer(
    p_competition_id in number,
    p_user_id in number,
    p_removed_by in number
  );
  -- update_competition_dates: Updates existing data for competition dates.
  procedure update_competition_dates(
    p_competition_id in number,
    p_starts_at in timestamp,
    p_ends_at in timestamp,
    p_updated_by in number
  );
  -- update_competition_meta: Updates existing data for competition meta.
  procedure update_competition_meta(
    p_competition_id in number,
    p_name in varchar2,
    p_description in varchar2,
    p_type in varchar2,
    p_status in varchar2,
    p_use_location in varchar2,
    p_show_competitor_location in varchar2,
    p_radius_m in number,
    p_updated_by in number
  );
  -- upsert_competition_declination: Saves a competition magnetic declination snapshot.
  procedure upsert_competition_declination(
    p_competition_id in number,
    p_declination in number
  );
  -- get_competition_terms_json: Returns a JSON object for the requested competition terms.
  procedure get_competition_terms_json(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_default_terms_text in clob,
    o_item_json out clob
  );
  -- set_competition_terms_text: Sets competition terms text values.
  procedure set_competition_terms_text(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_terms_text in clob,
    p_updated_by in number
  );
  -- get_participant_map_layers_json: Returns a JSON object for the requested participant map layers.
  procedure get_participant_map_layers_json(
    p_competition_id in number,
    o_items_json out clob
  );
  -- set_participant_map_layers: Sets participant map layers values.
  procedure set_participant_map_layers(
    p_competition_id in number,
    p_layer_codes_json in clob,
    p_updated_by in number
  );
  -- get_competition_map_overlay_json: Returns the active competition overlay JSON object.
  procedure get_competition_map_overlay_json(
    p_competition_id in number,
    o_item_json out clob
  );
  -- list_pending_competition_map_overlays_json: Returns active overlays waiting for processing or recovery.
  procedure list_pending_competition_map_overlays_json(
    o_items_json out clob
  );
  -- upsert_competition_map_overlay: Inserts or updates the active competition overlay metadata.
  procedure upsert_competition_map_overlay(
    p_competition_id in number,
    p_display_name in varchar2,
    p_image_file_name in varchar2,
    p_world_file_name in varchar2,
    p_image_mime_type in varchar2,
    p_image_size_bytes in number,
    p_storage_rel_path in varchar2,
    p_crs_code in varchar2,
    p_width_px in number,
    p_height_px in number,
    p_pixel_size_x in number,
    p_pixel_size_y in number,
    p_top_left_x in number,
    p_top_left_y in number,
    p_min_x in number,
    p_min_y in number,
    p_max_x in number,
    p_max_y in number,
    p_updated_by in number,
    o_overlay_id out number
  );
  -- set_competition_map_overlay_processing: Updates active competition overlay processing state and tile metadata.
  procedure set_competition_map_overlay_processing(
    p_overlay_id in number,
    p_processing_status in varchar2,
    p_processing_error in varchar2,
    p_tile_storage_rel_path in varchar2,
    p_tile_min_zoom in number,
    p_tile_max_zoom in number,
    p_updated_by in number
  );
  -- delete_competition_map_overlay: Soft-deletes the active competition overlay.
  procedure delete_competition_map_overlay(
    p_competition_id in number,
    p_updated_by in number
  );
  -- list_checkpoints_json: Returns a JSON array for the requested checkpoints.
  procedure list_checkpoints_json(p_competition_id in number, o_items_json out clob);
  -- upsert_access_code: Inserts or updates access code data.
  procedure upsert_access_code(
    p_competition_id in number,
    p_code_type in varchar2,
    p_code in varchar2,
    p_status in varchar2,
    p_expires_at in timestamp,
    p_max_uses in number,
    p_created_by in number,
    p_force_regenerate in varchar2 default 'N',
    o_access_code_id out number,
    o_code out varchar2
  );
  -- get_competition_overview_json: Returns a JSON object for the requested competition overview.
  procedure get_competition_overview_json(p_competition_id in number, o_overview_json out clob);
  -- get_questions_overview_json: Returns a JSON object for the requested questions overview.
  procedure get_questions_overview_json(p_competition_id in number, o_questions_json out clob);
  -- Lists translations filtered by language, key prefix, and include-deleted flag.
  procedure list_translations_json(
    p_lang in varchar2,
    p_prefix in varchar2,
    p_include_deleted in varchar2,
    o_items_json out clob
  );
  -- Inserts or updates a translation text for a given translation key and language.
  procedure upsert_translation(
    p_translation_key in varchar2,
    p_lang_code in varchar2,
    p_text_value in clob,
    p_updated_by in number
  );
  -- Soft-deletes a translation by marking it inactive (end-dated) for the given key and language.
  procedure soft_delete_translation(
    p_translation_key in varchar2,
    p_lang_code in varchar2,
    p_deleted_by in number
  );

  -- create_checkpoint: Creates a new checkpoint record.
  procedure create_checkpoint(
    p_competition_id in number,
    p_title in varchar2,
    p_checkpoint_type in varchar2,
    p_order_no in number,
    p_location_hint in varchar2,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    p_location_required in varchar2,
    p_created_by in number,
    o_checkpoint_id out number
  );
  -- update_checkpoint: Updates existing data for checkpoint.
  procedure update_checkpoint(
    p_checkpoint_id in number,
    p_title in varchar2,
    p_order_no in number,
    p_location_hint in varchar2,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    p_location_required in varchar2,
    p_updated_by in number
  );
  -- soft_delete_checkpoint: Soft-deletes the target record by end-dating it.
  procedure soft_delete_checkpoint(p_checkpoint_id in number, p_deleted_by in number);

  -- create_question: Creates a new question record.
  procedure create_question(
    p_checkpoint_id in number,
    p_question_type in varchar2,
    p_input_type in varchar2,
    p_input_max_length in number,
    p_input_pattern in varchar2,
    p_points in number,
    p_wrong_points in number,
    p_lang_code in varchar2,
    p_question_text in varchar2,
    p_created_by in number,
    o_question_id out number
  );
  -- update_question: Updates existing data for question.
  procedure update_question(
    p_question_id in number,
    p_checkpoint_id in number,
    p_question_type in varchar2,
    p_input_type in varchar2,
    p_input_max_length in number,
    p_input_pattern in varchar2,
    p_points in number,
    p_wrong_points in number,
    p_lang_code in varchar2,
    p_question_text in varchar2,
    p_updated_by in number
  );
  -- soft_delete_question: Soft-deletes the target record by end-dating it.
  procedure soft_delete_question(p_question_id in number, p_deleted_by in number);

  -- replace_question_options_et: Replaces existing records with the provided payload for question options et.
  procedure replace_question_options_et(
    p_question_id in number,
    p_options_json in clob,
    p_updated_by in number
  );

  -- replace_question_answers: Replaces existing records with the provided payload for question answers.
  procedure replace_question_answers(
    p_question_id in number,
    p_answers_json in clob,
    p_updated_by in number
  );
end pkg_admin_content;
/

create or replace package body pkg_admin_content as
  c_json_question_text constant varchar2(30) := 'question_text';
  c_json_updated_at constant varchar2(30) := 'updated_at';

  -- add_audit: Performs this business operation according to package rules.
  procedure add_audit(p_entity_type varchar2, p_entity_id number, p_action varchar2, p_by number, p_old clob, p_new clob) is
  begin
    insert into audit_log(audit_id, entity_type, entity_id, action_type, changed_by, changed_at, old_data_json, new_data_json)
    values (seq_audit_log.nextval, p_entity_type, p_entity_id, p_action, p_by, systimestamp, p_old, p_new);
  end;

  -- generate_unique_access_code: Generates and returns a new value with required uniqueness/format.
  function generate_unique_access_code return varchar2 is
    l_code varchar2(20);
    l_exists number;
  begin
    while true loop
      l_code := to_char(trunc(dbms_random.value(0, 1000000)), 'FM000000');
      select count(*) into l_exists from competition_access_codes c where c.code = l_code;
      exit when l_exists = 0;
    end loop;
    return l_code;
  end;

  -- list_competitions_json: Returns a JSON array for the requested competitions.
  procedure list_competitions_json(p_user_id in number, o_items_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'competition_id' value c.competition_id,
        'name' value c.name,
        'type' value nvl(c.type, 'R'),
        'status' value c.status, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
        'starts_at' value to_char(c.starts_at, pkg_common.c_iso_ts_format),
        'ends_at' value to_char(c.ends_at, pkg_common.c_iso_ts_format),
        'use_location' value nvl(c.use_location, 'N'),
        'show_competitor_location' value nvl(c.show_competitor_location, 'Y'),
        'is_active' value case when c.ends_at is null or c.ends_at > systimestamp then 'Y' else 'N' end
      ) returning clob
    )
      into o_items_json
      from competitions c
      join competition_organizers co on co.competition_id = c.competition_id
     where (c.end_date is null or c.end_date > sysdate)
       and co.user_id = p_user_id
       and (co.end_date is null or co.end_date > sysdate)
     order by c.starts_at, c.created_at;
    if o_items_json is null then o_items_json := '[]'; end if;
  end;

  -- list_all_competitions_json: Returns a JSON array for the requested all competitions.
  procedure list_all_competitions_json(o_items_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'competition_id' value c.competition_id,
        'name' value c.name,
        'description' value c.description,
        'type' value nvl(c.type, 'R'),
        'status' value c.status,
        'use_location' value nvl(c.use_location, 'N'),
        'show_competitor_location' value nvl(c.show_competitor_location, 'N'),
        'checkpoint_count' value (
          select count(*)
            from checkpoints cp
           where cp.competition_id = c.competition_id
             and (cp.end_date is null or cp.end_date > sysdate)
        ),
        'starts_at' value to_char(c.starts_at, pkg_common.c_iso_ts_format),
        'ends_at' value to_char(c.ends_at, pkg_common.c_iso_ts_format),
        'created_at' value to_char(c.created_at, pkg_common.c_iso_ts_format),
        c_json_updated_at value to_char(c.updated_at, pkg_common.c_iso_ts_format),
        'organizer_code' value ( -- NOSONAR: S1192 repeated literal accepted for script readability/stability
          select ac.code
            from competition_access_codes ac
           where ac.competition_id = c.competition_id
             and ac.code_type = 'ORGANIZER'
             and (ac.end_date is null or ac.end_date > sysdate)
           order by ac.created_at desc, ac.access_code_id desc
           fetch first 1 row only
        ),
        'organizers' value (
          select nvl(
            json_arrayagg(
              json_object(
                'user_id' value u.user_id,
                'full_name' value u.full_name,
                'email' value u.email
              ) returning clob
            ),
            to_clob('[]')
          )
            from competition_organizers co
            join users u
              on u.user_id = co.user_id
           where co.competition_id = c.competition_id
             and (co.end_date is null or co.end_date > sysdate)
        )
      ) returning clob
    )
      into o_items_json
      from (
        select *
          from competitions c
         where (c.end_date is null or c.end_date > sysdate)
         order by c.created_at desc nulls last, c.competition_id desc
      ) c;

    if o_items_json is null then o_items_json := '[]'; end if;
  end;

  -- create_empty_competition: Creates a new empty competition record.
  procedure create_empty_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  ) is
    l_name varchar2(200);
  begin
    l_name := trim(p_name);
    if l_name is null then
      raise_application_error(-20170, 'competition name is required');
    end if;

    pkg_competitions.create_competition(
      p_name => l_name,
      p_description => p_description,
      p_created_by => p_created_by,
      o_competition_id => o_competition_id
    );

    o_organizer_code := generate_unique_access_code();
    insert into competition_access_codes(
      access_code_id, competition_id, code, status, expires_at, max_uses, used_count, start_date, created_by, created_at, code_type
    ) values (
      seq_competition_access_codes.nextval,
      o_competition_id,
      o_organizer_code,
      'ACTIVE',
      null,
      null,
      0,
      trunc(sysdate),
      p_created_by,
      systimestamp,
      'ORGANIZER'
    );

    add_audit(
      'COMPETITION', -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      o_competition_id,
      'CREATE', -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      p_created_by,
      null,
      to_clob(
        json_object(
          'name' value l_name,
          'description' value p_description,
          'organizer_code' value o_organizer_code
        )
      )
    );
  end;

  -- copy_competition: Copies data from source entities according to provided flags.
  procedure copy_competition(
    p_source_competition_id in number,
    p_copy_questions in varchar2,
    p_copy_organizers in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  ) is
    l_copy_questions varchar2(1) := upper(trim(nvl(p_copy_questions, 'N')));
    l_copy_organizers varchar2(1) := upper(trim(nvl(p_copy_organizers, 'N')));
    l_name competitions.name%type;
    l_description competitions.description%type;
    l_type competitions.type%type;
    l_use_location competitions.use_location%type;
    l_show_competitor_location competitions.show_competitor_location%type;
    l_radius_m competitions.radius_m%type;
  begin
    if p_source_competition_id is null then
      raise_application_error(-20173, 'source competition is required');
    end if;
    if l_copy_questions not in ('Y', 'N') then
      raise_application_error(-20174, 'invalid copy_questions');
    end if;
    if l_copy_organizers not in ('Y', 'N') then
      raise_application_error(-20175, 'invalid copy_organizers');
    end if;

    begin
      select c.name,
             c.description,
             nvl(c.type, 'R'),
             nvl(c.use_location, 'N'),
             nvl(c.show_competitor_location, 'N'),
             c.radius_m
        into l_name,
             l_description,
             l_type,
             l_use_location,
             l_show_competitor_location,
             l_radius_m
        from competitions c
       where c.competition_id = p_source_competition_id
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20176, 'source competition not found');
    end;

    o_competition_id := seq_competitions.nextval;
    insert into competitions (
      competition_id, name, description, type, status, use_location, show_competitor_location, radius_m, start_date, created_by, created_at
    ) values (
      o_competition_id,
      substr(l_name || ' (koopia)', 1, 255),
      l_description,
      l_type,
      'DRAFT',
      l_use_location,
      case when l_use_location = 'Y' then l_show_competitor_location else 'N' end,
      l_radius_m,
      trunc(sysdate),
      p_created_by,
      systimestamp
    );

    o_organizer_code := generate_unique_access_code();
    insert into competition_access_codes(
      access_code_id, competition_id, code, status, expires_at, max_uses, used_count, start_date, created_by, created_at, code_type
    ) values (
      seq_competition_access_codes.nextval,
      o_competition_id,
      o_organizer_code,
      'ACTIVE',
      null,
      null,
      0,
      trunc(sysdate),
      p_created_by,
      systimestamp,
      'ORGANIZER'
    );

    if l_copy_organizers = 'Y' then
      insert into competition_organizers (
        competition_organizer_id, competition_id, user_id, start_date, end_date, assigned_by, assigned_at
      )
      select seq_competition_organizers.nextval,
             o_competition_id,
             co.user_id,
             trunc(sysdate),
             null,
             p_created_by,
             systimestamp
        from competition_organizers co
       where co.competition_id = p_source_competition_id
         and (co.end_date is null or co.end_date > sysdate);
    end if;

    if l_copy_questions = 'Y' then
      for cp in (
        select cp.checkpoint_id,
               cp.title,
               cp.checkpoint_type,
               cp.order_no,
               cp.location_hint,
               cp.latitude,
               cp.longitude,
               cp.radius_m,
               cp.location_required
          from checkpoints cp
         where cp.competition_id = p_source_competition_id
           and (cp.end_date is null or cp.end_date > sysdate)
         order by nvl(cp.order_no, 999999), cp.checkpoint_id
      ) loop
        declare
          l_new_checkpoint_id number;
        begin
          l_new_checkpoint_id := seq_checkpoints.nextval;
          insert into checkpoints (
            checkpoint_id, competition_id, title, checkpoint_type, order_no, location_hint, latitude, longitude, radius_m, location_required, start_date, created_by, created_at
          ) values (
            l_new_checkpoint_id, o_competition_id, cp.title, cp.checkpoint_type, cp.order_no, cp.location_hint, cp.latitude, cp.longitude, cp.radius_m, cp.location_required,
            trunc(sysdate), p_created_by, systimestamp
          );

          for q in (
            select q.question_id,
                   q.question_type,
                   q.input_type,
                   q.input_max_length,
                   q.input_pattern,
                   q.points,
                   q.wrong_points,
                   q.status
              from questions q
             where q.checkpoint_id = cp.checkpoint_id
               and (q.end_date is null or q.end_date > sysdate)
          ) loop
            declare
              l_new_question_id number;
            begin
              l_new_question_id := seq_questions.nextval;
              insert into questions (
                question_id, checkpoint_id, question_type, input_type, input_max_length, input_pattern, points, wrong_points, status, start_date, created_by, created_at
              ) values (
                l_new_question_id, l_new_checkpoint_id, q.question_type, q.input_type, q.input_max_length, q.input_pattern,
                nvl(q.points, 0), nvl(q.wrong_points, 0), q.status, trunc(sysdate), p_created_by, systimestamp
              );

              insert into question_texts (
                question_text_id, question_id, lang_code, question_text, start_date, created_by, created_at
              )
              select seq_question_texts.nextval,
                     l_new_question_id,
                     qt.lang_code,
                     qt.question_text,
                     trunc(sysdate),
                     p_created_by,
                     systimestamp
                from question_texts qt
               where qt.question_id = q.question_id
                 and (qt.end_date is null or qt.end_date > sysdate);

              insert into question_answers (
                answer_id, question_id, answer_value, is_correct, normalize_mode, start_date, created_by, created_at
              )
              select seq_question_answers.nextval,
                     l_new_question_id,
                     qa.answer_value,
                     qa.is_correct,
                     qa.normalize_mode,
                     trunc(sysdate),
                     p_created_by,
                     systimestamp
                from question_answers qa
               where qa.question_id = q.question_id
                 and (qa.end_date is null or qa.end_date > sysdate);

              for qo in (
                select qo.option_id,
                       qo.option_code,
                       qo.order_no,
                       qo.is_correct
                  from question_options qo
                 where qo.question_id = q.question_id
                   and (qo.end_date is null or qo.end_date > sysdate)
                 order by nvl(qo.order_no, 999999), qo.option_id
              ) loop
                declare
                  l_new_option_id number;
                begin
                  l_new_option_id := seq_question_options.nextval;
                  insert into question_options (
                    option_id, question_id, option_code, order_no, is_correct, start_date, created_by, created_at
                  ) values (
                    l_new_option_id, l_new_question_id, qo.option_code, qo.order_no, qo.is_correct, trunc(sysdate), p_created_by, systimestamp
                  );

                  insert into question_option_texts (
                    question_option_text_id, option_id, lang_code, option_text, start_date, created_by, created_at
                  )
                  select seq_question_option_texts.nextval,
                         l_new_option_id,
                         qot.lang_code,
                         qot.option_text,
                         trunc(sysdate),
                         p_created_by,
                         systimestamp
                    from question_option_texts qot
                   where qot.option_id = qo.option_id
                     and (qot.end_date is null or qot.end_date > sysdate);
                end;
              end loop;
            end;
          end loop;
        end;
      end loop;
    end if;

    add_audit(
      'COMPETITION',
      o_competition_id,
      'COPY',
      p_created_by,
      null,
      to_clob(
        json_object(
          'source_competition_id' value p_source_competition_id,
          'copy_questions' value l_copy_questions,
          'copy_organizers' value l_copy_organizers,
          'organizer_code' value o_organizer_code
        )
      )
    );
  end;

  -- remove_competition_organizer: Removes the requested relation or assignment.
  procedure remove_competition_organizer(
    p_competition_id in number,
    p_user_id in number,
    p_removed_by in number
  ) is
    l_competition_organizer_id number;
  begin
    if p_competition_id is null or p_user_id is null then
      raise_application_error(-20171, 'competition_id and user_id are required');
    end if;

    begin
      select co.competition_organizer_id
        into l_competition_organizer_id
        from competition_organizers co
       where co.competition_id = p_competition_id
         and co.user_id = p_user_id
         and (co.end_date is null or co.end_date > sysdate)
       order by co.assigned_at desc, co.competition_organizer_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20172, 'active organizer relation not found');
    end;

    update competition_organizers
       set end_date = trunc(sysdate)
     where competition_organizer_id = l_competition_organizer_id
       and (end_date is null or end_date > sysdate);

    add_audit(
      'COMPETITION_ORGANIZER',
      l_competition_organizer_id,
      'SOFT_DELETE', -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      p_removed_by,
      null,
      to_clob(
        json_object(
          'competition_id' value p_competition_id,
          'user_id' value p_user_id
        )
      )
    );
  end;

  -- update_competition_dates: Updates existing data for competition dates.
  procedure update_competition_dates(
    p_competition_id in number,
    p_starts_at in timestamp,
    p_ends_at in timestamp,
    p_updated_by in number
  ) is
  begin
    update competitions
       set starts_at = p_starts_at,
           ends_at = p_ends_at,
           updated_by = p_updated_by,
           updated_at = systimestamp
     where competition_id = p_competition_id
       and (end_date is null or end_date > sysdate);

    add_audit('COMPETITION', p_competition_id, 'UPDATE_DATES', p_updated_by, null,
      to_clob(json_object('starts_at' value to_char(p_starts_at, pkg_common.c_iso_ts_format), 'ends_at' value to_char(p_ends_at, pkg_common.c_iso_ts_format))));
  end;

  -- update_competition_meta: Updates existing data for competition meta.
  procedure update_competition_meta(
    p_competition_id in number,
    p_name in varchar2,
    p_description in varchar2,
    p_type in varchar2,
    p_status in varchar2,
    p_use_location in varchar2,
    p_show_competitor_location in varchar2,
    p_radius_m in number,
    p_updated_by in number
  ) is
    l_name varchar2(255) := trim(p_name);
    l_type varchar2(1) := upper(trim(nvl(p_type, 'R')));
    l_status varchar2(30) := upper(trim(p_status));
    l_use_location varchar2(1) := upper(trim(nvl(p_use_location, 'N')));
    l_show_competitor_location varchar2(1) := upper(trim(nvl(p_show_competitor_location, 'Y')));
  begin
    if l_name is null then
      raise_application_error(-20120, 'competition name is required');
    end if;
    if l_type not in ('R', 'S') then
      raise_application_error(-20125, 'invalid competition type');
    end if;
    if l_status not in ('ACTIVE', 'INACTIVE', 'DRAFT') then
      raise_application_error(-20121, 'invalid competition status');
    end if;
    if l_use_location not in ('Y','N') then
      raise_application_error(-20122, 'invalid use_location');
    end if;
    if l_show_competitor_location not in ('Y','N') then
      raise_application_error(-20124, 'invalid show_competitor_location');
    end if;
    if l_use_location <> 'Y' then
      l_show_competitor_location := 'N';
    end if;
    if p_radius_m is not null and p_radius_m <= 0 then
      raise_application_error(-20123, 'radius_m must be > 0');
    end if;

    update competitions
       set name = l_name,
           description = p_description,
           type = l_type,
           status = l_status,
           use_location = l_use_location,
           show_competitor_location = l_show_competitor_location,
           radius_m = p_radius_m,
           updated_by = p_updated_by,
           updated_at = systimestamp
     where competition_id = p_competition_id
       and (end_date is null or end_date > sysdate);

    add_audit('COMPETITION', p_competition_id, 'UPDATE_META', p_updated_by, null,
      to_clob(json_object(
        'name' value l_name,
        'description' value p_description,
        'type' value l_type,
        'status' value l_status,
        'use_location' value l_use_location,
        'show_competitor_location' value l_show_competitor_location,
        'radius_m' value p_radius_m
      )));
  end;

  -- upsert_competition_declination: Saves a competition magnetic declination snapshot.
  procedure upsert_competition_declination(
    p_competition_id in number,
    p_declination in number
  ) is
  begin
    merge into competition_declinations cd
    using (
      select p_competition_id as competition_id,
             p_declination as declination
        from dual
    ) src
      on (cd.competition_id = src.competition_id)
    when matched then
      update set cd.declination = src.declination,
                 cd.last_updated = systimestamp
    when not matched then
      insert (competition_id, declination, last_updated)
      values (src.competition_id, src.declination, systimestamp);
  end;

  -- get_competition_terms_json: Returns a JSON object for the requested competition terms.
  procedure get_competition_terms_json(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_default_terms_text in clob,
    o_item_json out clob
  ) is
    l_terms_id number;
    l_lang varchar2(10) := lower(nvl(trim(p_lang_code), 'et'));
    l_terms_lang_code varchar2(10);
    l_terms_text clob;
    l_dummy number;
  begin
    o_item_json := null;
    if p_competition_id is null then
      return;
    end if;

    begin
      select 1
        into l_dummy
        from competitions c
       where c.competition_id = p_competition_id
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        return;
    end;

    begin
      select t.terms_id
        into l_terms_id
        from competition_terms t
       where t.competition_id = p_competition_id
         and t.status = 'ACTIVE'
         and (t.end_date is null or t.end_date > sysdate)
       order by t.terms_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        if p_default_terms_text is null then
          return;
        end if;
        l_terms_id := seq_competition_terms.nextval;
        insert into competition_terms (
          terms_id, competition_id, version_no, status, start_date, created_by, created_at
        ) values (
          l_terms_id, p_competition_id, 1, 'ACTIVE', trunc(sysdate), null, systimestamp
        );
    end;

    begin
      select lower(tt.lang_code), tt.terms_text
        into l_terms_lang_code, l_terms_text
        from competition_terms_texts tt
       where tt.terms_id = l_terms_id
         and lower(tt.lang_code) = l_lang
         and (tt.end_date is null or tt.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        if p_default_terms_text is not null then
          insert into competition_terms_texts (
            terms_text_id, terms_id, lang_code, terms_text, start_date, created_by, created_at
          ) values (
            seq_competition_terms_texts.nextval, l_terms_id, l_lang, p_default_terms_text, trunc(sysdate), null, systimestamp
          );
          l_terms_lang_code := l_lang;
          l_terms_text := p_default_terms_text;
        else
          begin
            select lower(tt.lang_code), tt.terms_text
              into l_terms_lang_code, l_terms_text
              from competition_terms_texts tt
             where tt.terms_id = l_terms_id
               and (tt.end_date is null or tt.end_date > sysdate)
             order by tt.lang_code
             fetch first 1 row only;
          exception
            when no_data_found then
              return;
          end;
        end if;
    end;

    select json_object(
             'competition_id' value p_competition_id,
             'terms' value json_object(
               'terms_id' value l_terms_id,
               'lang_code' value l_terms_lang_code,
               'terms_text' value l_terms_text
             )
             returning clob
           )
      into o_item_json
      from dual;
  end;

  -- set_competition_terms_text: Sets competition terms text values.
  procedure set_competition_terms_text(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_terms_text in clob,
    p_updated_by in number
  ) is
    l_terms_id number;
    l_lang varchar2(10) := lower(nvl(trim(p_lang_code), 'et'));
  begin
    if p_competition_id is null then
      raise_application_error(-20180, 'competition_id is required');
    end if;
    if trim(dbms_lob.substr(p_terms_text, 4000, 1)) is null then
      raise_application_error(-20181, 'terms_text is required');
    end if;

    begin
      select t.terms_id
        into l_terms_id
        from competition_terms t
       where t.competition_id = p_competition_id
         and t.status = 'ACTIVE'
         and (t.end_date is null or t.end_date > sysdate)
       order by t.terms_id desc
       fetch first 1 row only;
    exception
      when no_data_found then
        l_terms_id := seq_competition_terms.nextval;
        insert into competition_terms (
          terms_id, competition_id, version_no, status, start_date, created_by, created_at
        ) values (
          l_terms_id, p_competition_id, 1, 'ACTIVE', trunc(sysdate), p_updated_by, systimestamp
        );
    end;

    update competition_terms_texts
       set terms_text = p_terms_text,
           updated_by = p_updated_by,
           updated_at = systimestamp
     where terms_id = l_terms_id
       and lower(lang_code) = l_lang
       and (end_date is null or end_date > sysdate);

    if sql%rowcount = 0 then
      insert into competition_terms_texts (
        terms_text_id, terms_id, lang_code, terms_text, start_date, created_by, created_at
      ) values (
        seq_competition_terms_texts.nextval, l_terms_id, l_lang, p_terms_text, trunc(sysdate), p_updated_by, systimestamp
      );
    end if;

    add_audit(
      'COMPETITION_TERMS',
      l_terms_id,
      'UPSERT_TEXT',
      p_updated_by,
      null,
      to_clob(json_object('competition_id' value p_competition_id, 'lang_code' value l_lang))
    );
  end;

  -- get_participant_map_layers_json: Returns a JSON object for the requested participant map layers.
  procedure get_participant_map_layers_json(
    p_competition_id in number,
    o_items_json out clob
  ) is
    l_now_utc_date date;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);
    select json_arrayagg(
             json_object('layer_code' value cpml.layer_code) returning clob
           )
      into o_items_json
      from competition_participant_map_layers cpml
     where cpml.competition_id = p_competition_id
       and (cpml.end_date is null or cpml.end_date > l_now_utc_date)
     order by lower(cpml.layer_code), cpml.competition_participant_map_layer_id;
    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- set_participant_map_layers: Sets participant map layers values.
  procedure set_participant_map_layers(
    p_competition_id in number,
    p_layer_codes_json in clob,
    p_updated_by in number
  ) is
    l_codes json_array_t;
    l_count pls_integer;
    l_code varchar2(100);
    l_norm_code varchar2(100);
    l_now_utc_date date;
    type t_code_set is table of pls_integer index by varchar2(100);
    l_selected_set t_code_set;
    l_existing_set t_code_set;
    type t_code_list is table of varchar2(100) index by pls_integer;
    l_selected_list t_code_list;
    l_selected_count pls_integer := 0;
    l_change_count pls_integer := 0;
    l_has_epk pls_integer := 0;
    l_has_epk_overlay pls_integer := 0;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);

    if p_competition_id is null then
      raise_application_error(-20180, 'competition_id is required');
    end if;
    if p_layer_codes_json is null then
      raise_application_error(-20181, 'layer_codes_json is required');
    end if;

    l_codes := json_array_t.parse(p_layer_codes_json);
    l_count := l_codes.get_size;
    if l_count > 0 then
      for i in 0 .. l_count - 1 loop
        l_code := trim(l_codes.get_string(i));
        if l_code is null then
          continue;
        end if;
        l_norm_code := lower(l_code);
        if not l_selected_set.exists(l_norm_code) then
          l_selected_count := l_selected_count + 1;
          l_selected_list(l_selected_count) := l_norm_code;
          l_selected_set(l_norm_code) := 1;
        end if;
        if l_norm_code = 'maaamet_pohikaart' then
          l_has_epk := 1;
        elsif l_norm_code = 'maaamet_pohikaart_overlay' then
          l_has_epk_overlay := 1;
        end if;
      end loop;
    end if;

    if l_selected_count < 1 then
      raise_application_error(-20182, 'at least one layer must be selected');
    end if;
    if l_has_epk_overlay = 1 and l_has_epk = 0 then
      raise_application_error(-20183, 'maaamet_pohikaart is required when maaamet_pohikaart_overlay is selected');
    end if;

    for rec in (
      select competition_participant_map_layer_id, lower(layer_code) as layer_code
        from competition_participant_map_layers
       where competition_id = p_competition_id
         and (end_date is null or end_date > l_now_utc_date)
    ) loop
      l_existing_set(rec.layer_code) := 1;
      if not l_selected_set.exists(rec.layer_code) then
        update competition_participant_map_layers
           set end_date = greatest(start_date, l_now_utc_date),
               updated_by = p_updated_by,
               updated_at = systimestamp
         where competition_participant_map_layer_id = rec.competition_participant_map_layer_id;
        l_change_count := l_change_count + 1;
      end if;
    end loop;

    for i in 1 .. l_selected_count loop
      l_norm_code := l_selected_list(i);
      if not l_existing_set.exists(l_norm_code) then
        insert into competition_participant_map_layers (
          competition_participant_map_layer_id,
          competition_id,
          layer_code,
          start_date,
          created_by,
          created_at
        ) values (
          seq_competition_part_map_layers.nextval,
          p_competition_id,
          l_norm_code,
          l_now_utc_date,
          p_updated_by,
          systimestamp
        );
        l_change_count := l_change_count + 1;
      end if;
    end loop;

    if l_change_count > 0 then
      add_audit(
        'COMPETITION',
        p_competition_id,
        'UPDATE_PARTICIPANT_MAP_LAYERS',
        p_updated_by,
        null,
        p_layer_codes_json
      );
    end if;
  end;

  -- get_competition_map_overlay_json: Returns the active competition overlay JSON object.
  procedure get_competition_map_overlay_json(
    p_competition_id in number,
    o_item_json out clob
  ) is
    l_now_utc_date date;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);

    begin
      select json_object(
               'overlay_id' value cmo.overlay_id,
               'competition_id' value cmo.competition_id,
               'display_name' value cmo.display_name,
               'image_file_name' value cmo.image_file_name,
               'world_file_name' value cmo.world_file_name,
               'image_mime_type' value cmo.image_mime_type,
               'image_size_bytes' value cmo.image_size_bytes,
               'storage_rel_path' value cmo.storage_rel_path,
               'processing_status' value cmo.processing_status,
               'processing_error' value cmo.processing_error,
               'tile_storage_rel_path' value cmo.tile_storage_rel_path,
               'tile_min_zoom' value cmo.tile_min_zoom,
               'tile_max_zoom' value cmo.tile_max_zoom,
               'tiles_generated_at' value to_char(cmo.tiles_generated_at, pkg_common.c_iso_ts_format),
               'crs_code' value cmo.crs_code,
               'width_px' value cmo.width_px,
               'height_px' value cmo.height_px,
               'pixel_size_x' value cmo.pixel_size_x,
               'pixel_size_y' value cmo.pixel_size_y,
               'top_left_x' value cmo.top_left_x,
               'top_left_y' value cmo.top_left_y,
               'min_x' value cmo.min_x,
               'min_y' value cmo.min_y,
               'max_x' value cmo.max_x,
               'max_y' value cmo.max_y,
               'updated_at' value to_char(cmo.updated_at, pkg_common.c_iso_ts_format),
               'created_at' value to_char(cmo.created_at, pkg_common.c_iso_ts_format)
               returning clob
             )
        into o_item_json
        from competition_map_overlays cmo
       where cmo.competition_id = p_competition_id
         and (cmo.end_date is null or cmo.end_date > l_now_utc_date)
       fetch first 1 row only;
    exception
      when no_data_found then
        o_item_json := null;
    end;
  end;

  -- list_pending_competition_map_overlays_json: Returns active overlays waiting for processing or recovery.
  procedure list_pending_competition_map_overlays_json(
    o_items_json out clob
  ) is
    l_now_utc_date date;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);

    select json_arrayagg(
             json_object(
               'overlay_id' value cmo.overlay_id,
               'competition_id' value cmo.competition_id,
               'display_name' value cmo.display_name,
               'image_file_name' value cmo.image_file_name,
               'world_file_name' value cmo.world_file_name,
               'image_mime_type' value cmo.image_mime_type,
               'image_size_bytes' value cmo.image_size_bytes,
               'storage_rel_path' value cmo.storage_rel_path,
               'processing_status' value cmo.processing_status,
               'processing_error' value cmo.processing_error,
               'tile_storage_rel_path' value cmo.tile_storage_rel_path,
               'tile_min_zoom' value cmo.tile_min_zoom,
               'tile_max_zoom' value cmo.tile_max_zoom,
               'tiles_generated_at' value to_char(cmo.tiles_generated_at, pkg_common.c_iso_ts_format),
               'crs_code' value cmo.crs_code,
               'width_px' value cmo.width_px,
               'height_px' value cmo.height_px,
               'pixel_size_x' value cmo.pixel_size_x,
               'pixel_size_y' value cmo.pixel_size_y,
               'top_left_x' value cmo.top_left_x,
               'top_left_y' value cmo.top_left_y,
               'min_x' value cmo.min_x,
               'min_y' value cmo.min_y,
               'max_x' value cmo.max_x,
               'max_y' value cmo.max_y,
               'updated_at' value to_char(cmo.updated_at, pkg_common.c_iso_ts_format),
               'created_at' value to_char(cmo.created_at, pkg_common.c_iso_ts_format)
               returning clob
             ) returning clob
           )
      into o_items_json
      from competition_map_overlays cmo
     where (cmo.end_date is null or cmo.end_date > l_now_utc_date)
       and upper(trim(nvl(cmo.processing_status, 'UPLOADED'))) in ('UPLOADED', 'PROCESSING');

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- upsert_competition_map_overlay: Inserts or updates the active competition overlay metadata.
  procedure upsert_competition_map_overlay(
    p_competition_id in number,
    p_display_name in varchar2,
    p_image_file_name in varchar2,
    p_world_file_name in varchar2,
    p_image_mime_type in varchar2,
    p_image_size_bytes in number,
    p_storage_rel_path in varchar2,
    p_crs_code in varchar2,
    p_width_px in number,
    p_height_px in number,
    p_pixel_size_x in number,
    p_pixel_size_y in number,
    p_top_left_x in number,
    p_top_left_y in number,
    p_min_x in number,
    p_min_y in number,
    p_max_x in number,
    p_max_y in number,
    p_updated_by in number,
    o_overlay_id out number
  ) is
    l_now_utc_date date;
    l_overlay_id competition_map_overlays.overlay_id%type;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);

    if p_competition_id is null then
      raise_application_error(-20184, 'competition_id is required');
    end if;
    if trim(p_display_name) is null then
      raise_application_error(-20185, 'display_name is required');
    end if;
    if trim(p_image_file_name) is null or trim(p_world_file_name) is null then
      raise_application_error(-20186, 'image and world file names are required');
    end if;
    if upper(trim(nvl(p_crs_code, ''))) <> 'EPSG:3301' then
      raise_application_error(-20187, 'only EPSG:3301 overlays are supported');
    end if;

    begin
      select cmo.overlay_id
        into l_overlay_id
        from competition_map_overlays cmo
       where cmo.competition_id = p_competition_id
         and (cmo.end_date is null or cmo.end_date > l_now_utc_date)
       fetch first 1 row only
       for update;

      update competition_map_overlays
         set display_name = trim(p_display_name),
             image_file_name = trim(p_image_file_name),
             world_file_name = trim(p_world_file_name),
             image_mime_type = trim(p_image_mime_type),
             image_size_bytes = p_image_size_bytes,
             storage_rel_path = trim(p_storage_rel_path),
             processing_status = 'UPLOADED',
             processing_error = null,
             tile_storage_rel_path = null,
             tile_min_zoom = null,
             tile_max_zoom = null,
             tiles_generated_at = null,
             crs_code = upper(trim(p_crs_code)),
             width_px = p_width_px,
             height_px = p_height_px,
             pixel_size_x = p_pixel_size_x,
             pixel_size_y = p_pixel_size_y,
             top_left_x = p_top_left_x,
             top_left_y = p_top_left_y,
             min_x = p_min_x,
             min_y = p_min_y,
             max_x = p_max_x,
             max_y = p_max_y,
             updated_by = p_updated_by,
             updated_at = systimestamp
       where overlay_id = l_overlay_id;
    exception
      when no_data_found then
        l_overlay_id := seq_competition_map_overlays.nextval;
        insert into competition_map_overlays (
          overlay_id,
          competition_id,
          display_name,
          image_file_name,
          world_file_name,
          image_mime_type,
          image_size_bytes,
          storage_rel_path,
          processing_status,
          processing_error,
          tile_storage_rel_path,
          tile_min_zoom,
          tile_max_zoom,
          tiles_generated_at,
          crs_code,
          width_px,
          height_px,
          pixel_size_x,
          pixel_size_y,
          top_left_x,
          top_left_y,
          min_x,
          min_y,
          max_x,
          max_y,
          start_date,
          created_by,
          created_at
        ) values (
          l_overlay_id,
          p_competition_id,
          trim(p_display_name),
          trim(p_image_file_name),
          trim(p_world_file_name),
          trim(p_image_mime_type),
          p_image_size_bytes,
          trim(p_storage_rel_path),
          'UPLOADED',
          null,
          null,
          null,
          null,
          null,
          upper(trim(p_crs_code)),
          p_width_px,
          p_height_px,
          p_pixel_size_x,
          p_pixel_size_y,
          p_top_left_x,
          p_top_left_y,
          p_min_x,
          p_min_y,
          p_max_x,
          p_max_y,
          l_now_utc_date,
          p_updated_by,
          systimestamp
        );
    end;

    o_overlay_id := l_overlay_id;
  end;

  -- set_competition_map_overlay_processing: Updates active competition overlay processing state and tile metadata.
  procedure set_competition_map_overlay_processing(
    p_overlay_id in number,
    p_processing_status in varchar2,
    p_processing_error in varchar2,
    p_tile_storage_rel_path in varchar2,
    p_tile_min_zoom in number,
    p_tile_max_zoom in number,
    p_updated_by in number
  ) is
    l_norm_status varchar2(20);
  begin
    l_norm_status := upper(trim(nvl(p_processing_status, '')));
    if l_norm_status not in ('UPLOADED', 'PROCESSING', 'READY', 'FAILED') then
      raise_application_error(-20189, 'invalid overlay processing status');
    end if;

    update competition_map_overlays
       set processing_status = l_norm_status,
           processing_error = case
             when l_norm_status = 'FAILED' then substr(p_processing_error, 1, 2000)
             else null
           end,
           tile_storage_rel_path = case
             when l_norm_status = 'READY' then trim(p_tile_storage_rel_path)
             else null
           end,
           tile_min_zoom = case
             when l_norm_status = 'READY' then p_tile_min_zoom
             else null
           end,
           tile_max_zoom = case
             when l_norm_status = 'READY' then p_tile_max_zoom
             else null
           end,
           tiles_generated_at = case
             when l_norm_status = 'READY' then systimestamp
             else null
           end,
           updated_by = p_updated_by,
           updated_at = systimestamp
     where overlay_id = p_overlay_id
       and (end_date is null or end_date > cast((systimestamp at time zone 'UTC') as date));
  end;

  -- delete_competition_map_overlay: Soft-deletes the active competition overlay.
  procedure delete_competition_map_overlay(
    p_competition_id in number,
    p_updated_by in number
  ) is
    l_now_utc_date date;
  begin
    l_now_utc_date := cast((systimestamp at time zone 'UTC') as date);

    update competition_map_overlays
       set end_date = greatest(start_date, l_now_utc_date),
           updated_by = p_updated_by,
           updated_at = systimestamp
     where competition_id = p_competition_id
       and (end_date is null or end_date > l_now_utc_date);
  end;

  -- list_checkpoints_json: Returns a JSON array for the requested checkpoints.
  procedure list_checkpoints_json(p_competition_id in number, o_items_json out clob) is
  begin
    select json_arrayagg(json_object(
      'checkpoint_id' value cp.checkpoint_id,
      'title' value cp.title, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      'checkpoint_type' value pkg_common.normalize_checkpoint_type(cp.checkpoint_type),
      'order_no' value cp.order_no, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      'location_hint' value cp.location_hint, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      'latitude' value cp.latitude,
      'longitude' value cp.longitude,
      'radius_m' value cp.radius_m,
      'location_required' value cp.location_required
    ) returning clob)
      into o_items_json
      from checkpoints cp
     where cp.competition_id = p_competition_id
       and (cp.end_date is null or cp.end_date > sysdate)
     order by nvl(cp.order_no, 999999), cp.checkpoint_id;
    if o_items_json is null then o_items_json := '[]'; end if;
  end;

  -- upsert_access_code: Inserts or updates access code data.
  procedure upsert_access_code(
    p_competition_id in number, p_code_type in varchar2, p_code in varchar2, p_status in varchar2,
    p_expires_at in timestamp, p_max_uses in number, p_created_by in number,
    p_force_regenerate in varchar2 default 'N', o_access_code_id out number, o_code out varchar2
  ) is
    l_code varchar2(20);
    l_conflict number;
    l_existing_code varchar2(20);
    l_force_regenerate varchar2(1);
  begin
    l_code := trim(p_code);
    l_force_regenerate := case
      when upper(trim(nvl(p_force_regenerate, 'N'))) in ('Y', '1', 'TRUE', 'YES') then 'Y'
      else 'N'
    end;

    begin
      select c.access_code_id, c.code
        into o_access_code_id, l_existing_code
        from competition_access_codes c
       where c.competition_id = p_competition_id
         and c.code_type = p_code_type
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception when no_data_found then
      o_access_code_id := null;
      l_existing_code := null;
    end;

    if l_force_regenerate = 'Y' then
      l_code := generate_unique_access_code;
    elsif l_code is null then
      if o_access_code_id is not null then
        l_code := l_existing_code;
      else
        l_code := generate_unique_access_code;
      end if;
    end if;

    select count(*) into l_conflict
      from competition_access_codes c
     where c.code = l_code
       and not (c.competition_id = p_competition_id and c.code_type = p_code_type and (c.end_date is null or c.end_date > sysdate));
    if l_conflict > 0 then raise_application_error(-20140, 'access code must be globally unique'); end if;

    begin
      if o_access_code_id is null then
        raise no_data_found;
      end if;
      update competition_access_codes
         set code = l_code, status = nvl(p_status, status), expires_at = p_expires_at, max_uses = p_max_uses
       where access_code_id = o_access_code_id;

      add_audit('ACCESS_CODE', o_access_code_id, 'UPSERT', p_created_by, null,
        to_clob(json_object('competition_id' value p_competition_id, 'code_type' value p_code_type, 'code' value l_code)));
    exception when no_data_found then
      o_access_code_id := seq_competition_access_codes.nextval;
      insert into competition_access_codes(access_code_id, competition_id, code, code_type, status, expires_at, max_uses, used_count, start_date, created_by, created_at)
      values (o_access_code_id, p_competition_id, l_code, p_code_type, nvl(p_status, 'ACTIVE'), p_expires_at, p_max_uses, 0, trunc(sysdate), p_created_by, systimestamp);

      add_audit('ACCESS_CODE', o_access_code_id, 'CREATE', p_created_by, null,
        to_clob(json_object('competition_id' value p_competition_id, 'code_type' value p_code_type, 'code' value l_code)));
    end;
    o_code := l_code;
  end;

  -- get_competition_overview_json: Returns a JSON object for the requested competition overview.
  procedure get_competition_overview_json(p_competition_id in number, o_overview_json out clob) is
    l_dummy number;
    l_dummy_code varchar2(20);
  begin
    begin
      upsert_access_code(p_competition_id, 'COMPETITOR', null, 'ACTIVE', null, null, null, 'N', l_dummy, l_dummy_code);
      upsert_access_code(p_competition_id, 'ORGANIZER', null, 'ACTIVE', null, null, null, 'N', l_dummy, l_dummy_code);
    exception when others then null; end;

    select json_object(
      'competition_id' value c.competition_id,
      'name' value c.name,
      'description' value c.description,
      'type' value nvl(c.type, 'R'),
      'status' value c.status,
      'use_location' value c.use_location,
      'show_competitor_location' value c.show_competitor_location,
      'radius_m' value c.radius_m,
      'declination' value nvl(cd.declination, 0),
      'declination_last_updated' value to_char(cd.last_updated, pkg_common.c_iso_ts_format),
      'starts_at' value to_char(c.starts_at, pkg_common.c_iso_ts_format),
      'ends_at' value to_char(c.ends_at, pkg_common.c_iso_ts_format),
      'created_at' value to_char(c.created_at, pkg_common.c_iso_ts_format),
      c_json_updated_at value to_char(c.updated_at, pkg_common.c_iso_ts_format),
      'competitor_code' value (select json_object('code' value x.code, 'status' value x.status, 'expires_at' value to_char(x.expires_at, pkg_common.c_iso_ts_format)) from competition_access_codes x where x.competition_id=c.competition_id and x.code_type='COMPETITOR' and (x.end_date is null or x.end_date > sysdate) fetch first 1 row only),
      'organizer_code' value (select json_object('code' value x.code, 'status' value x.status, 'expires_at' value to_char(x.expires_at, pkg_common.c_iso_ts_format)) from competition_access_codes x where x.competition_id=c.competition_id and x.code_type='ORGANIZER' and (x.end_date is null or x.end_date > sysdate) fetch first 1 row only),
      'organizers' value (select json_arrayagg(json_object('user_id' value u.user_id, 'full_name' value u.full_name, 'email' value u.email) returning clob) from competition_organizers co join users u on u.user_id=co.user_id where co.competition_id=c.competition_id and (co.end_date is null or co.end_date > sysdate)),
      'question_count' value (select count(*) from questions q join checkpoints cp on cp.checkpoint_id=q.checkpoint_id where cp.competition_id=c.competition_id and (q.end_date is null or q.end_date > sysdate) and (cp.end_date is null or cp.end_date > sysdate))
      returning clob
    ) into o_overview_json
      from competitions c
      left join competition_declinations cd
        on cd.competition_id = c.competition_id
     where c.competition_id = p_competition_id
       and (c.end_date is null or c.end_date > sysdate);
  end;

  -- get_questions_overview_json: Returns a JSON object for the requested questions overview.
  procedure get_questions_overview_json(p_competition_id in number, o_questions_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'checkpoint_id' value cp.checkpoint_id,
        'checkpoint_title' value cp.title,
        'checkpoint_order_no' value cp.order_no,
        'checkpoint_type' value pkg_common.normalize_checkpoint_type(cp.checkpoint_type),
        'location_hint' value cp.location_hint,
        'latitude' value cp.latitude,
        'longitude' value cp.longitude,
        'radius_m' value cp.radius_m,
        'location_required' value cp.location_required,
        'question_id' value q.question_id,
        'question_type' value q.question_type,
        'points' value q.points,
        'wrong_points' value q.wrong_points,
        'question_status' value q.status,
        'text_et' value (select qt.question_text from question_texts qt where qt.question_id=q.question_id and lower(qt.lang_code)='et' and (qt.end_date is null or qt.end_date > sysdate) fetch first 1 row only),
        'text_en' value (select qt.question_text from question_texts qt where qt.question_id=q.question_id and lower(qt.lang_code)='en' and (qt.end_date is null or qt.end_date > sysdate) fetch first 1 row only),
        'options' value (
          select json_arrayagg(
            json_object(
              'option_id' value qo.option_id,
              'option_code' value qo.option_code,
              'order_no' value qo.order_no,
              'is_correct' value qo.is_correct,
              'text_et' value (select qot.option_text from question_option_texts qot where qot.option_id=qo.option_id and lower(qot.lang_code)='et' and (qot.end_date is null or qot.end_date > sysdate) fetch first 1 row only),
              'text_en' value (select qot.option_text from question_option_texts qot where qot.option_id=qo.option_id and lower(qot.lang_code)='en' and (qot.end_date is null or qot.end_date > sysdate) fetch first 1 row only)
            ) returning clob
          )
          from question_options qo
          where qo.question_id=q.question_id and (qo.end_date is null or qo.end_date > sysdate)
        ),
        'answers' value (select json_arrayagg(json_object('answer_id' value qa.answer_id,'answer_value' value qa.answer_value,'normalize_mode' value qa.normalize_mode,'is_correct' value qa.is_correct) returning clob) from question_answers qa where qa.question_id=q.question_id and (qa.end_date is null or qa.end_date > sysdate)) -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      )
      returning clob
    ) into o_questions_json
      from checkpoints cp
      left join questions q on q.checkpoint_id = cp.checkpoint_id and (q.end_date is null or q.end_date > sysdate)
     where cp.competition_id = p_competition_id
       and (cp.end_date is null or cp.end_date > sysdate)
     order by nvl(cp.order_no, 999999), cp.checkpoint_id;

    if o_questions_json is null then o_questions_json := '[]'; end if;
  end;

  -- list_translations_json: Returns a JSON array for the requested translations.
  procedure list_translations_json(
    p_lang in varchar2,
    p_prefix in varchar2,
    p_include_deleted in varchar2,
    o_items_json out clob
  ) is
    l_lang varchar2(10) := lower(trim(nvl(p_lang, '')));
    l_prefix varchar2(300) := trim(nvl(p_prefix, ''));
    l_include_deleted varchar2(1) := upper(trim(nvl(p_include_deleted, 'N')));
  begin
    select json_arrayagg(
             json_object(
               'translation_key' value t.translation_key,
               'lang_code' value t.lang_code,
               'text_value' value t.text_value,
               'is_deleted' value case when t.end_date is null then 'N' else 'Y' end,
               c_json_updated_at value case when t.updated_at is not null then to_char(t.updated_at, pkg_common.c_iso_ts_format) else null end
             returning clob
             ) returning clob
           )
      into o_items_json
      from translations t
     where (l_lang is null or lower(t.lang_code) = l_lang)
       and (l_prefix is null or lower(t.translation_key) like lower(l_prefix) || '%')
       and (l_include_deleted = 'Y' or t.end_date is null);

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  -- upsert_translation: Inserts or updates translation data.
  procedure upsert_translation(
    p_translation_key in varchar2,
    p_lang_code in varchar2,
    p_text_value in clob,
    p_updated_by in number
  ) is
    l_key varchar2(300) := trim(p_translation_key);
    l_lang varchar2(10) := lower(trim(p_lang_code));
    l_text clob := p_text_value;
  begin
    if l_key is null or l_lang is null then
      raise_application_error(-20190, 'translation_key and lang_code are required');
    end if;

    update translations t
       set t.text_value = l_text,
           t.end_date = null,
           t.updated_at = systimestamp,
           t.updated_by = p_updated_by
     where t.translation_key = l_key
       and lower(t.lang_code) = l_lang
       and t.end_date is null;

    if sql%rowcount = 0 then
      insert into translations (
        translation_id, translation_key, lang_code, text_value,
        start_date, created_at, created_by, updated_at, updated_by
      ) values (
        seq_translations.nextval, l_key, l_lang, l_text,
        trunc(sysdate), systimestamp, p_updated_by, systimestamp, p_updated_by
      );
    end if;
  end;

  -- soft_delete_translation: Soft-deletes the target record by end-dating it.
  procedure soft_delete_translation(
    p_translation_key in varchar2,
    p_lang_code in varchar2,
    p_deleted_by in number
  ) is
    l_key varchar2(300) := trim(p_translation_key);
    l_lang varchar2(10) := lower(trim(p_lang_code));
  begin
    if l_key is null or l_lang is null then
      raise_application_error(-20191, 'translation_key and lang_code are required');
    end if;

    update translations t
       set t.end_date = trunc(sysdate),
           t.updated_at = systimestamp,
           t.updated_by = p_deleted_by
     where t.translation_key = l_key
       and lower(t.lang_code) = l_lang
       and t.end_date is null;
  end;

  -- create_checkpoint: Creates a new checkpoint record.
  procedure create_checkpoint(p_competition_id in number, p_title in varchar2, p_checkpoint_type in varchar2, p_order_no in number, p_location_hint in varchar2, p_latitude in number, p_longitude in number, p_radius_m in number, p_location_required in varchar2, p_created_by in number, o_checkpoint_id out number) is -- NOSONAR: API boundary procedure mirrors checkpoint payload shape
    l_dummy number;
    l_use_location varchar2(1);
    l_comp_type varchar2(1) := 'R';
    l_location_required varchar2(1) := upper(trim(nvl(p_location_required, 'N')));
    l_checkpoint_type varchar2(10) := pkg_common.normalize_checkpoint_type(p_checkpoint_type);
    l_title checkpoints.title%type := trim(p_title);
    l_order_no checkpoints.order_no%type := p_order_no;
    l_special_exists number := 0;
  begin
    if p_competition_id is null then
      raise_application_error(-20100, 'competition_id and title are required');
    end if;

    if l_checkpoint_type = pkg_common.c_checkpoint_type_start then
      l_title := pkg_common.c_checkpoint_type_start;
      l_order_no := pkg_common.c_checkpoint_start_order;
    elsif l_checkpoint_type = pkg_common.c_checkpoint_type_finish then
      l_title := pkg_common.c_checkpoint_type_finish;
      l_order_no := pkg_common.c_checkpoint_finish_order;
    elsif l_title is null then
      raise_application_error(-20100, 'competition_id and title are required');
    end if;

    if l_checkpoint_type = pkg_common.c_checkpoint_type_normal
       and upper(trim(l_title)) in (pkg_common.c_checkpoint_type_start, pkg_common.c_checkpoint_type_finish) then
      raise_application_error(-20196, 'checkpoint title is reserved for special checkpoint types');
    end if;

    if l_checkpoint_type = pkg_common.c_checkpoint_type_normal
       and l_order_no in (pkg_common.c_checkpoint_start_order, pkg_common.c_checkpoint_finish_order) then
      raise_application_error(-20197, 'order_no is reserved for start and finish checkpoints');
    end if;

    begin
      select 1 into l_dummy from checkpoints cp
       where cp.competition_id=p_competition_id and upper(trim(cp.title))=upper(trim(l_title)) and (cp.end_date is null or cp.end_date > sysdate)
       fetch first 1 row only;
      raise_application_error(-20101, 'checkpoint title already exists in this competition');
    exception when no_data_found then null; end;

    select use_location, nvl(type, 'R')
      into l_use_location, l_comp_type
      from competitions
     where competition_id = p_competition_id
       and (end_date is null or end_date > sysdate);
    if l_comp_type = 'S' and l_order_no is null then
      raise_application_error(-20126, 'order_no is required for competition type S');
    end if;
    if l_use_location <> 'Y' then
      l_location_required := 'N';
    end if;
    if l_location_required not in ('Y','N') then
      raise_application_error(-20105, 'invalid location_required');
    end if;

    if l_checkpoint_type in (pkg_common.c_checkpoint_type_start, pkg_common.c_checkpoint_type_finish) then
      select count(*)
        into l_special_exists
        from checkpoints cp
       where cp.competition_id = p_competition_id
         and pkg_common.normalize_checkpoint_type(cp.checkpoint_type) = l_checkpoint_type
         and (cp.end_date is null or cp.end_date > sysdate);
      if l_special_exists > 0 then
        raise_application_error(-20198, 'special checkpoint type already exists in this competition');
      end if;
    end if;

    o_checkpoint_id := seq_checkpoints.nextval;
    insert into checkpoints(checkpoint_id, competition_id, title, checkpoint_type, order_no, location_hint, latitude, longitude, radius_m, location_required, start_date, created_by, created_at)
    values(o_checkpoint_id, p_competition_id, l_title, l_checkpoint_type, l_order_no, p_location_hint, p_latitude, p_longitude, p_radius_m, l_location_required, trunc(sysdate), p_created_by, systimestamp);

    add_audit('CHECKPOINT', o_checkpoint_id, 'CREATE', p_created_by, null, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      to_clob(json_object('competition_id' value p_competition_id,'title' value l_title,'checkpoint_type' value l_checkpoint_type,'order_no' value l_order_no)));
  end;

  -- update_checkpoint: Updates existing data for checkpoint.
  procedure update_checkpoint(p_checkpoint_id in number, p_title in varchar2, p_order_no in number, p_location_hint in varchar2, p_latitude in number, p_longitude in number, p_radius_m in number, p_location_required in varchar2, p_updated_by in number) is
    l_competition_id number;
    l_dummy number;
    l_use_location varchar2(1);
    l_comp_type varchar2(1) := 'R';
    l_location_required varchar2(1) := upper(trim(nvl(p_location_required, 'N')));
    l_checkpoint_type varchar2(10) := pkg_common.c_checkpoint_type_normal;
    l_title checkpoints.title%type := trim(p_title);
    l_order_no checkpoints.order_no%type := p_order_no;
  begin
    if p_checkpoint_id is null or trim(p_title) is null then raise_application_error(-20102, 'checkpoint_id and title are required'); end if;

    select competition_id,
           pkg_common.normalize_checkpoint_type(checkpoint_type)
      into l_competition_id,
           l_checkpoint_type
      from checkpoints
     where checkpoint_id = p_checkpoint_id
       and (end_date is null or end_date > sysdate);
    select use_location, nvl(type, 'R')
      into l_use_location, l_comp_type
      from competitions
     where competition_id = l_competition_id
       and (end_date is null or end_date > sysdate);
    if l_checkpoint_type = pkg_common.c_checkpoint_type_start then
      l_title := pkg_common.c_checkpoint_type_start;
      l_order_no := pkg_common.c_checkpoint_start_order;
    elsif l_checkpoint_type = pkg_common.c_checkpoint_type_finish then
      l_title := pkg_common.c_checkpoint_type_finish;
      l_order_no := pkg_common.c_checkpoint_finish_order;
    elsif upper(trim(l_title)) in (pkg_common.c_checkpoint_type_start, pkg_common.c_checkpoint_type_finish) then
      raise_application_error(-20196, 'checkpoint title is reserved for special checkpoint types');
    elsif l_order_no in (pkg_common.c_checkpoint_start_order, pkg_common.c_checkpoint_finish_order) then
      raise_application_error(-20197, 'order_no is reserved for start and finish checkpoints');
    end if;
    if l_comp_type = 'S' and l_order_no is null then
      raise_application_error(-20127, 'order_no is required for competition type S');
    end if;
    if l_use_location <> 'Y' then
      l_location_required := 'N';
    end if;
    if l_location_required not in ('Y','N') then
      raise_application_error(-20106, 'invalid location_required');
    end if;

    begin
      select 1 into l_dummy from checkpoints cp
       where cp.competition_id=l_competition_id and cp.checkpoint_id<>p_checkpoint_id and upper(trim(cp.title))=upper(trim(l_title)) and (cp.end_date is null or cp.end_date > sysdate)
       fetch first 1 row only;
      raise_application_error(-20103, 'checkpoint title already exists in this competition');
    exception when no_data_found then null; end;

    update checkpoints
       set title=l_title, order_no=l_order_no, location_hint=p_location_hint,
           latitude = p_latitude, longitude = p_longitude, radius_m = p_radius_m, location_required = l_location_required,
           updated_by=p_updated_by, updated_at=systimestamp
     where checkpoint_id = p_checkpoint_id;

    add_audit('CHECKPOINT', p_checkpoint_id, 'UPDATE', p_updated_by, null,
      to_clob(json_object('title' value l_title, 'checkpoint_type' value l_checkpoint_type, 'order_no' value l_order_no, 'location_hint' value p_location_hint, 'latitude' value p_latitude, 'longitude' value p_longitude, 'radius_m' value p_radius_m, 'location_required' value l_location_required)));
  end;

  -- soft_delete_checkpoint: Soft-deletes the target record by end-dating it.
  procedure soft_delete_checkpoint(p_checkpoint_id in number, p_deleted_by in number) is
    l_cnt number;
  begin
    select count(*) into l_cnt from questions q where q.checkpoint_id = p_checkpoint_id and (q.end_date is null or q.end_date > sysdate);
    if l_cnt > 0 then raise_application_error(-20104, 'cannot delete checkpoint with active questions'); end if;

    update checkpoints
       set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where checkpoint_id = p_checkpoint_id and (end_date is null or end_date > sysdate);

    add_audit('CHECKPOINT', p_checkpoint_id, 'SOFT_DELETE', p_deleted_by, null, null);
  end;

  -- create_question: Creates a new question record.
  procedure create_question(
    p_checkpoint_id in number, p_question_type in varchar2, p_input_type in varchar2, p_input_max_length in number,
    p_input_pattern in varchar2, p_points in number, p_wrong_points in number, p_lang_code in varchar2,
    p_question_text in varchar2, p_created_by in number, o_question_id out number
  ) is
    l_lang varchar2(10);
    l_exists number;
  begin
    if p_checkpoint_id is null or p_question_type is null or trim(p_question_text) is null then
      raise_application_error(-20110, 'checkpoint_id, question_type and question_text are required');
    end if;

    select count(*) into l_exists
      from questions q
     where q.checkpoint_id = p_checkpoint_id
       and (q.end_date is null or q.end_date > sysdate);
    if l_exists > 0 then
      raise_application_error(-20113, 'target checkpoint already has another active question');
    end if;

    l_lang := nvl(p_lang_code, 'et');
    o_question_id := seq_questions.nextval;
    insert into questions(question_id, checkpoint_id, question_type, input_type, input_max_length, input_pattern, points, wrong_points, status, start_date, created_by, created_at)
    values(o_question_id, p_checkpoint_id, p_question_type, p_input_type, p_input_max_length, p_input_pattern, nvl(p_points,0), nvl(p_wrong_points,0), 'ACTIVE', trunc(sysdate), p_created_by, systimestamp);

    insert into question_texts(question_text_id, question_id, lang_code, question_text, start_date, created_by, created_at)
    values(seq_question_texts.nextval, o_question_id, l_lang, trim(p_question_text), trunc(sysdate), p_created_by, systimestamp);

    add_audit('QUESTION', o_question_id, 'CREATE', p_created_by, null, -- NOSONAR: S1192 repeated literal accepted for script readability/stability
      to_clob(json_object('checkpoint_id' value p_checkpoint_id, 'question_type' value p_question_type, c_json_question_text value trim(p_question_text))));
  end;

  -- update_question: Updates existing data for question.
  procedure update_question(
    p_question_id in number, p_checkpoint_id in number, p_question_type in varchar2, p_input_type in varchar2,
    p_input_max_length in number, p_input_pattern in varchar2, p_points in number, p_wrong_points in number,
    p_lang_code in varchar2, p_question_text in varchar2, p_updated_by in number
  ) is
    l_lang varchar2(10);
  begin
    if p_question_id is null or p_checkpoint_id is null or p_question_type is null or trim(p_question_text) is null then
      raise_application_error(-20115, 'question_id, checkpoint_id, question_type and question_text are required');
    end if;
    l_lang := nvl(p_lang_code, 'et');

    update questions
       set checkpoint_id = p_checkpoint_id, question_type = p_question_type, input_type = p_input_type,
           input_max_length = p_input_max_length, input_pattern = p_input_pattern, points = nvl(p_points,0), wrong_points = nvl(p_wrong_points,0),
           updated_by = p_updated_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    update question_texts
       set question_text = trim(p_question_text), updated_by = p_updated_by, updated_at = systimestamp
     where question_id = p_question_id and lower(lang_code)=lower(l_lang) and (end_date is null or end_date > sysdate);

    if sql%rowcount = 0 then
      insert into question_texts(question_text_id, question_id, lang_code, question_text, start_date, created_by, created_at)
      values(seq_question_texts.nextval, p_question_id, l_lang, trim(p_question_text), trunc(sysdate), p_updated_by, systimestamp);
    end if;

    add_audit('QUESTION', p_question_id, 'UPDATE', p_updated_by, null,
      to_clob(json_object('checkpoint_id' value p_checkpoint_id, 'question_type' value p_question_type, c_json_question_text value trim(p_question_text))));
  end;

  -- soft_delete_question: Soft-deletes the target record by end-dating it.
  procedure soft_delete_question(p_question_id in number, p_deleted_by in number) is
  begin
    update question_answers set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    update question_option_texts set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where option_id in (select option_id from question_options where question_id = p_question_id and (end_date is null or end_date > sysdate))
       and (end_date is null or end_date > sysdate);

    update question_options set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    update question_texts set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    update questions set end_date = trunc(sysdate), updated_by = p_deleted_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    add_audit('QUESTION', p_question_id, 'SOFT_DELETE', p_deleted_by, null, null);
  end;

  -- replace_question_options_et: Replaces existing records with the provided payload for question options et.
  procedure replace_question_options_et(p_question_id in number, p_options_json in clob, p_updated_by in number) is
    l_arr json_array_t;
    l_obj json_object_t;
    l_keys json_key_list;
    l_k pls_integer;
    l_option_id number;
    l_text varchar2(4000);
    l_code varchar2(100);
    l_is_correct varchar2(1);
    l_order_no number;
    l_key varchar2(200);
    l_lang varchar2(20);
    l_existing_option_id number;
    l_found number;
    type t_code_set is table of varchar2(100) index by varchar2(100);
    l_payload_codes t_code_set;
    l_norm_code varchar2(100);
  begin
    if p_options_json is not null then
      l_arr := json_array_t.parse(p_options_json);
      for i in 0 .. l_arr.get_size - 1 loop
        l_obj := treat(l_arr.get(i) as json_object_t);
        l_code := l_obj.get_string('option_code');
        l_text := l_obj.get_string('text_et');
        l_is_correct := case when l_obj.has('is_correct') and upper(l_obj.get_string('is_correct'))='Y' then 'Y' else 'N' end;
        l_norm_code := upper(trim(l_code));
        if l_norm_code is null then
          continue;
        end if;
        l_payload_codes(l_norm_code) := l_norm_code;

        begin
          select qo.option_id
            into l_existing_option_id
            from question_options qo
           where qo.question_id = p_question_id
             and upper(trim(qo.option_code)) = l_norm_code
             and (qo.end_date is null or qo.end_date > sysdate)
           fetch first 1 row only;
        exception
          when no_data_found then
            l_existing_option_id := null;
        end;

        if l_existing_option_id is null then
          select nvl(max(qo.order_no), 0) + 1
            into l_order_no
            from question_options qo
           where qo.question_id = p_question_id
             and (qo.end_date is null or qo.end_date > sysdate);
          l_option_id := seq_question_options.nextval;
          insert into question_options(option_id, question_id, option_code, order_no, is_correct, start_date, created_by, created_at)
          values(l_option_id, p_question_id, l_code, l_order_no, l_is_correct, trunc(sysdate), p_updated_by, systimestamp);
        else
          l_option_id := l_existing_option_id;
          update question_options
             set is_correct = l_is_correct,
                 updated_by = p_updated_by,
                 updated_at = systimestamp
           where option_id = l_option_id
             and (end_date is null or end_date > sysdate);
        end if;

        if l_text is not null and trim(l_text) is not null then
          update question_option_texts
             set option_text = l_text,
                 updated_by = p_updated_by,
                 updated_at = systimestamp
           where option_id = l_option_id
             and lower(lang_code) = 'et'
             and (end_date is null or end_date > sysdate);
          if sql%rowcount = 0 then
            insert into question_option_texts(question_option_text_id, option_id, lang_code, option_text, start_date, created_by, created_at)
            values(seq_question_option_texts.nextval, l_option_id, 'et', l_text, trunc(sysdate), p_updated_by, systimestamp);
          end if;
        end if;

        l_keys := l_obj.get_keys;
        l_k := 1;
        while l_k <= l_keys.count loop
          l_key := l_keys(l_k);
          if l_key not like 'text\_%' escape '\' or lower(l_key) = 'text_et' then
            l_k := l_k + 1;
            continue;
          end if;

          l_lang := lower(substr(l_key, 6));
          l_text := l_obj.get_string(l_key);
          if l_text is null or trim(l_text) is null then
            l_k := l_k + 1;
            continue;
          end if;

          update question_option_texts
             set option_text = l_text,
                 updated_by = p_updated_by,
                 updated_at = systimestamp
           where option_id = l_option_id
             and lower(lang_code) = l_lang
             and (end_date is null or end_date > sysdate);
          if sql%rowcount = 0 then
            insert into question_option_texts(question_option_text_id, option_id, lang_code, option_text, start_date, created_by, created_at)
            values(seq_question_option_texts.nextval, l_option_id, l_lang, l_text, trunc(sysdate), p_updated_by, systimestamp);
          end if;
          l_k := l_k + 1;
        end loop;
      end loop;
      for old_opt in (
        select qo.option_id,
               upper(trim(qo.option_code)) as norm_code
          from question_options qo
         where qo.question_id = p_question_id
           and (qo.end_date is null or qo.end_date > sysdate)
      ) loop
        if old_opt.norm_code is null then
          l_found := 0;
        elsif l_payload_codes.exists(old_opt.norm_code) then
          l_found := 1;
        else
          l_found := 0;
        end if;
        if l_found = 0 then
          update question_option_texts
             set end_date = trunc(sysdate),
                 updated_by = p_updated_by,
                 updated_at = systimestamp
           where option_id = old_opt.option_id
             and (end_date is null or end_date > sysdate);

          update question_options
             set end_date = trunc(sysdate),
                 updated_by = p_updated_by,
                 updated_at = systimestamp
           where option_id = old_opt.option_id
             and (end_date is null or end_date > sysdate);
        end if;
      end loop;
    end if;
  end;

  -- replace_question_answers: Replaces existing records with the provided payload for question answers.
  procedure replace_question_answers(p_question_id in number, p_answers_json in clob, p_updated_by in number) is
    l_arr json_array_t;
    l_obj json_object_t;
    l_val varchar2(4000);
    l_norm varchar2(30);
    l_is_correct varchar2(1);
  begin
    update question_answers set end_date = trunc(sysdate), updated_by = p_updated_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    if p_answers_json is null then return; end if;
    l_arr := json_array_t.parse(p_answers_json);
    for i in 0 .. l_arr.get_size - 1 loop
      l_obj := treat(l_arr.get(i) as json_object_t);
      l_val := l_obj.get_string('answer_value');
      l_norm := case when l_obj.has('normalize_mode') then l_obj.get_string('normalize_mode') else 'EXACT' end;
      l_is_correct := case when l_obj.has('is_correct') and upper(l_obj.get_string('is_correct'))='Y' then 'Y' else 'N' end;
      insert into question_answers(answer_id, question_id, answer_value, is_correct, normalize_mode, start_date, created_by, created_at)
      values(seq_question_answers.nextval, p_question_id, l_val, l_is_correct, l_norm, trunc(sysdate), p_updated_by, systimestamp);
    end loop;
  end;
end pkg_admin_content;
/
