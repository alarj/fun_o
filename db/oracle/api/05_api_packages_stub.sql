-- 05_api_packages_stub.sql
-- Run as FUNO_APP

create or replace package pkg_auth as
  procedure upsert_google_user(
    p_google_sub in varchar2,
    p_email in varchar2,
    p_full_name in varchar2,
    o_user_id out number
  );

  procedure resolve_user_for_dev(
    p_user_id in number,
    p_email in varchar2,
    o_user_id out number
  );

  procedure has_active_role(
    p_user_id in number,
    p_role_code in varchar2,
    o_has_role out varchar2
  );

  procedure get_user_profile(
    p_user_id in number,
    o_email out varchar2,
    o_full_name out varchar2
  );
end pkg_auth;
/

create or replace package body pkg_auth as
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

create or replace package pkg_competitions as
  procedure create_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number
  );

  procedure register_to_competition(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  );

  procedure add_organizer(
    p_competition_id in number,
    p_target_user_id in number,
    p_assigned_by in number
  );

  procedure register_organizer_by_code(
    p_user_id in number,
    p_access_code in varchar2,
    o_competition_id out number
  );
end pkg_competitions;
/

create or replace package body pkg_competitions as
  procedure create_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number
  ) is
  begin
    if p_name is null then
      raise_application_error(-20020, 'competition name is required');
    end if;

    o_competition_id := seq_competitions.nextval;
    insert into competitions (
      competition_id, name, description, status, show_competitor_location, start_date, created_by, created_at
    ) values (
      o_competition_id, p_name, p_description, 'DRAFT', 'N', trunc(sysdate), p_created_by, systimestamp
    );
  end;

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
      raise_application_error(-20030, 'access_code is required');
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
         and c.code_type = 'COMPETITOR'
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > l_now_utc_ts)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and comp.status = 'ACTIVE'
         and (comp.starts_at is null or comp.starts_at <= l_now_utc_ts)
         and (comp.ends_at is null or comp.ends_at > l_now_utc_ts)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20031, 'invalid or inactive access code');
    end;

    if l_max_uses is not null and l_used_count >= l_max_uses then
      raise_application_error(-20032, 'access code usage limit reached');
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
         and c.code_type = 'ORGANIZER'
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
  procedure create_question(
    p_checkpoint_id in number,
    p_question_text in varchar2,
    p_question_type in varchar2,
    p_points in number,
    p_created_by in number,
    o_question_id out number
  );

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

create or replace package pkg_submissions as
  function normalize_text(
    p_value in varchar2,
    p_mode in varchar2
  ) return varchar2 deterministic;

  procedure submit_answer(
    p_user_id in number,
    p_competition_id in number,
    p_checkpoint_id in number,
    p_question_id in number,
    p_answer_text in clob,
    p_selected_option_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_submission_id out number,
    o_is_correct out varchar2,
    o_awarded_points out number,
    o_total_score out number
  );
end pkg_submissions;
/

create or replace package body pkg_submissions as
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

  procedure submit_answer(
    p_user_id in number,
    p_competition_id in number,
    p_checkpoint_id in number,
    p_question_id in number,
    p_answer_text in clob,
    p_selected_option_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_submission_id out number,
    o_is_correct out varchar2,
    o_awarded_points out number,
    o_total_score out number
  ) is
    l_dummy number;
    l_question_type questions.question_type%type;
    l_input_type questions.input_type%type;
    l_awarded_points questions.points%type := 0;
    l_wrong_points questions.wrong_points%type := 0;
    l_is_correct varchar2(1) := 'N';
    l_normalized_answer varchar2(4000);
    l_correct_count number := 0;
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
      select q.question_type, q.input_type, q.points, q.wrong_points
        into l_question_type, l_input_type, l_awarded_points, l_wrong_points
        from questions q
       where q.question_id = p_question_id
         and q.checkpoint_id = p_checkpoint_id
         and (q.end_date is null or q.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20062, 'question not found or inactive');
    end;

    if l_question_type = 'SINGLE_CHOICE' then
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
  end;
end pkg_submissions;
/

create or replace package pkg_i18n as
  procedure get_translations_json(
    p_lang_code in varchar2,
    p_default_lang_code in varchar2,
    o_items_json out clob
  );
end pkg_i18n;
/

create or replace package body pkg_i18n as
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

create or replace package pkg_results as
  procedure get_competition_score(
    p_competition_id in number,
    p_user_id in number,
    o_score out number
  );

  procedure get_competition_leaderboard(
    p_competition_id in number,
    o_items_json out clob
  );

  procedure get_participant_submissions(
    p_competition_id in number,
    p_user_id in number,
    o_items_json out clob
  );

  procedure get_submission_detail(
    p_competition_id in number,
    p_user_id in number,
    p_submission_id in number,
    o_item_json out clob
  );

  procedure get_checkpoint_results(
    p_competition_id in number,
    o_items_json out clob
  );

  procedure get_checkpoint_responders(
    p_competition_id in number,
    p_checkpoint_id in number,
    o_items_json out clob
  );
end pkg_results;
/

create or replace package body pkg_results as
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

  procedure get_competition_leaderboard(
    p_competition_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'user_id' value x.user_id,
               'competitor_name' value x.competitor_name,
               'answered_checkpoints' value x.answered_checkpoints,
               'score' value x.score,
               'last_checkpoint' value x.last_checkpoint,
               'last_submission_at' value case
                 when x.last_submission_at is not null then to_char(x.last_submission_at, 'YYYY-MM-DD"T"HH24:MI:SS')
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
               max(s.submitted_at) as last_submission_at
          from submissions s
          left join checkpoints c
            on c.checkpoint_id = s.checkpoint_id
          left join (
            select p.competition_id,
                   p.user_id,
                   p.alias_display,
                   row_number() over (
                     partition by p.competition_id, p.user_id
                     order by nvl(p.joined_at, timestamp '1900-01-01 00:00:00') desc,
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
         order by score desc, s.user_id
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  procedure get_participant_submissions(
    p_competition_id in number,
    p_user_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'checkpoint_title' value x.checkpoint_title,
               'submission_id' value x.submission_id,
               'submitted_at' value case
                 when x.submitted_at is not null then to_char(x.submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS')
                 else null
               end,
               'awarded_points' value x.awarded_points,
               'answer_text' value x.answer_text,
               'is_correct' value x.is_correct
             ) returning clob
           )
      into o_items_json
      from (
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
                         and lower(qot_et.lang_code) = 'et'
                       fetch first 1 row only
                    ),
                    nvl(
                      (
                        select qot_en.option_text
                          from question_option_texts qot_en
                         where qot_en.option_id = s.selected_option_id
                           and lower(qot_en.lang_code) = 'en'
                         fetch first 1 row only
                      ),
                      qo.option_code
                    )
                  )
                  else dbms_lob.substr(s.answer_text, 4000, 1)
                end as answer_text,
               case when nvl(s.is_correct, 'N') = 'Y' then 'Y' else 'N' end as is_correct
          from submissions s
          join checkpoints cp
            on cp.checkpoint_id = s.checkpoint_id
          join questions q
            on q.question_id = s.question_id
          left join question_options qo
            on qo.option_id = s.selected_option_id
         where s.competition_id = p_competition_id
           and s.user_id = p_user_id
         order by s.submitted_at desc, s.submission_id desc
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  procedure get_submission_detail(
    p_competition_id in number,
    p_user_id in number,
    p_submission_id in number,
    o_item_json out clob
  ) is
    l_question_id questions.question_id%type;
    l_question_type questions.question_type%type;
    l_selected_option_id submissions.selected_option_id%type;
    l_answer_text clob;
  begin
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
             'question_text' value qt.question_text,
             'question_type' value q.question_type,
             'points' value nvl(q.points, 0),
             'wrong_points' value nvl(q.wrong_points, 0),
             'submitted_at' value case
               when s.submitted_at is not null then to_char(s.submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS')
               else null
             end,
             'awarded_points' value nvl(s.awarded_points, 0),
             'competitor_answer' value case
               when q.question_type = 'SINGLE_CHOICE' then nvl(
                 (
                   select qot_et.option_text
                     from question_option_texts qot_et
                    where qot_et.option_id = s.selected_option_id
                      and lower(qot_et.lang_code) = 'et'
                      and qot_et.start_date <= cast(s.submitted_at as date)
                      and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 nvl(
                   (
                     select qot_en.option_text
                       from question_option_texts qot_en
                      where qot_en.option_id = s.selected_option_id
                        and lower(qot_en.lang_code) = 'en'
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
             'options' value case
               when q.question_type = 'SINGLE_CHOICE' then (
                 select json_arrayagg(
                          json_object(
                            'option_text' value nvl(
                              (
                                select qot_et.option_text
                                  from question_option_texts qot_et
                                 where qot_et.option_id = qo.option_id
                                   and lower(qot_et.lang_code) = 'et'
                                   and qot_et.start_date <= cast(s.submitted_at as date)
                                   and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                                 fetch first 1 row only
                              ),
                              nvl(
                                (
                                  select qot_en.option_text
                                    from question_option_texts qot_en
                                   where qot_en.option_id = qo.option_id
                                     and lower(qot_en.lang_code) = 'en'
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
       and lower(qt.lang_code) = 'et'
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

  procedure get_checkpoint_results(
    p_competition_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'checkpoint_id' value x.checkpoint_id,
               'checkpoint_title' value x.checkpoint_title,
               'last_submission_at' value case
                 when x.last_submission_at is not null then to_char(x.last_submission_at, 'YYYY-MM-DD"T"HH24:MI:SS')
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

  procedure get_checkpoint_responders(
    p_competition_id in number,
    p_checkpoint_id in number,
    o_items_json out clob
  ) is
  begin
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
  procedure get_session_by_participant_json(
    p_user_id in number,
    p_competition_participant_id in number,
    o_item_json out clob
  );

  procedure join_preview_json(
    p_user_id in number,
    p_access_code in varchar2,
    p_lang_code in varchar2,
    p_alias_display in varchar2,
    o_item_json out clob
  );

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

  procedure list_my_competitions_json(
    p_user_id in number,
    o_items_json out clob
  );
  procedure get_terms_for_competition_json(
    p_user_id in number,
    p_competition_id in number,
    p_lang_code in varchar2,
    o_item_json out clob
  );

  procedure list_open_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    o_items_json out clob
  );

  procedure list_map_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob
  );
  procedure get_progress_json(
    p_user_id in number,
    p_competition_id in number,
    o_progress_json out clob
  );

  procedure list_my_submissions_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob
  );

  procedure get_my_submission_detail_json(
    p_user_id in number,
    p_competition_id in number,
    p_submission_id in number,
    o_item_json out clob
  );
end pkg_competitor;
/

create or replace package body pkg_competitor as
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
               'competition_id' value c.competition_id,
               'competition_name' value c.name,
               'competition_description' value c.description,
               'alias_display' value cp.alias_display,
               'competitor_name' value nvl(nullif(trim(cp.alias_display), ''), nvl(nullif(trim(u.full_name), ''), '---')),
               'use_location' value nvl(c.use_location, 'N'),
               'show_competitor_location' value nvl(c.show_competitor_location, 'Y')
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
         and c.status in ('INACTIVE', 'ACTIVE')
       fetch first 1 row only;
    exception
      when no_data_found then
        o_item_json := null;
    end;
  end;

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
      raise_application_error(-20131, 'user is already active participant for this competition');
    end if;

    if p_alias_display is not null and trim(p_alias_display) is not null then
      begin
        select 1
          into l_used_count
          from competition_participants cp
         where cp.competition_id = l_competition_id
           and cp.end_date is null
           and nlssort(trim(cp.alias_display), 'NLS_SORT=BINARY_CI') =
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
             'terms' value json_object(
               'terms_id' value l_terms_id,
               'lang_code' value l_terms_lang_code,
               'terms_text' value l_terms_text
             )
             returning clob
           )
      into o_item_json
      from competitions c
     where c.competition_id = l_competition_id;
  end;

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
               'description' value x.description,
               'starts_at' value case when x.starts_at is not null then to_char(x.starts_at, 'YYYY-MM-DD"T"HH24:MI:SS') else null end,
               'ends_at' value case when x.ends_at is not null then to_char(x.ends_at, 'YYYY-MM-DD"T"HH24:MI:SS') else null end,
               'use_location' value nvl(x.use_location, 'N'),
               'show_competitor_location' value nvl(x.show_competitor_location, 'Y')
             ) returning clob
           )
      into o_items_json
      from (
        select c.competition_id,
               c.name,
               c.description,
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
  begin
    begin
      select nvl(c.use_location, 'N'), c.radius_m
        into l_use_location, l_comp_radius
        from competitions c
       where c.competition_id = p_competition_id
         and (c.end_date is null or c.end_date > sysdate)
       fetch first 1 row only;
    exception
      when no_data_found then
        l_use_location := 'N';
        l_comp_radius := null;
    end;

    select json_arrayagg(
             json_object(
               'checkpoint_id' value z.checkpoint_id,
               'checkpoint_title' value z.checkpoint_title,
               'question_id' value z.question_id,
               'question_type' value z.question_type,
               'points' value z.points,
               'text_et' value z.text_et,
               'text_en' value z.text_en,
               'input_type' value z.input_type,
               'input_max_length' value z.input_max_length,
               'latitude' value z.latitude,
               'longitude' value z.longitude,
               'radius_m' value z.radius_m,
               'location_required' value z.location_required,
               'options' value nvl(z.options_json, '[]') format json
             )
             order by z.sort_location_group, z.sort_distance_m, z.sort_title
             returning clob
           )
      into o_items_json
      from (
        select cp.checkpoint_id,
               cp.title as checkpoint_title,
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
                            'option_code' value qo.option_code,
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
         group by cp.checkpoint_id, cp.title, cp.order_no, q.question_id, q.question_type, q.points, q.input_type, q.input_max_length,
                  cp.latitude, cp.longitude, cp.radius_m, cp.location_required
      ) z;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

  procedure list_map_checkpoints_json(
    p_user_id in number,
    p_competition_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'checkpoint_id' value x.checkpoint_id,
               'checkpoint_title' value x.checkpoint_title,
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
      into o_items_json
      from (
        select cp.checkpoint_id,
               cp.title as checkpoint_title,
               q.question_id,
               q.points,
               cp.latitude,
               cp.longitude,
               cp.radius_m,
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
          join questions q
            on q.checkpoint_id = cp.checkpoint_id
         where cp.competition_id = p_competition_id
           and (cp.end_date is null or cp.end_date > sysdate)
           and (q.end_date is null or q.end_date > sysdate)
           and cp.latitude is not null
           and cp.longitude is not null
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;

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
                 when x.submitted_at is not null then to_char(x.submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS')
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

  procedure get_my_submission_detail_json(
    p_user_id in number,
    p_competition_id in number,
    p_submission_id in number,
    o_item_json out clob
  ) is
  begin
    select json_object(
             'submission_id' value s.submission_id,
             'checkpoint_title' value cp.title,
             'question_text' value qt.question_text,
             'question_type' value q.question_type,
             'points' value nvl(q.points, 0),
             'wrong_points' value nvl(q.wrong_points, 0),
             'submitted_at' value case
               when s.submitted_at is not null then to_char(s.submitted_at, 'YYYY-MM-DD"T"HH24:MI:SS')
               else null
             end,
             'awarded_points' value nvl(s.awarded_points, 0),
             'competitor_answer' value case
               when q.question_type = 'SINGLE_CHOICE' then nvl(
                 (
                   select qot_et.option_text
                     from question_option_texts qot_et
                    where qot_et.option_id = s.selected_option_id
                      and lower(qot_et.lang_code) = 'et'
                      and qot_et.start_date <= cast(s.submitted_at as date)
                      and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                    fetch first 1 row only
                 ),
                 nvl(
                   (
                     select qot_en.option_text
                       from question_option_texts qot_en
                      where qot_en.option_id = s.selected_option_id
                        and lower(qot_en.lang_code) = 'en'
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
                                   and lower(qot_et.lang_code) = 'et'
                                   and qot_et.start_date <= cast(s.submitted_at as date)
                                   and (qot_et.end_date is null or qot_et.end_date > cast(s.submitted_at as date))
                                 fetch first 1 row only
                              ),
                              nvl(
                                (
                                  select qot_en.option_text
                                    from question_option_texts qot_en
                                   where qot_en.option_id = qo.option_id
                                     and lower(qot_en.lang_code) = 'en'
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
       and lower(qt.lang_code) = 'et'
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
  procedure list_competitions_json(p_user_id in number, o_items_json out clob);
  procedure list_all_competitions_json(o_items_json out clob);
  procedure create_empty_competition(
    p_name in varchar2,
    p_description in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  );
  procedure copy_competition(
    p_source_competition_id in number,
    p_copy_questions in varchar2,
    p_copy_organizers in varchar2,
    p_created_by in number,
    o_competition_id out number,
    o_organizer_code out varchar2
  );
  procedure remove_competition_organizer(
    p_competition_id in number,
    p_user_id in number,
    p_removed_by in number
  );
  procedure update_competition_dates(
    p_competition_id in number,
    p_starts_at in timestamp,
    p_ends_at in timestamp,
    p_updated_by in number
  );
  procedure update_competition_meta(
    p_competition_id in number,
    p_name in varchar2,
    p_description in varchar2,
    p_status in varchar2,
    p_use_location in varchar2,
    p_show_competitor_location in varchar2,
    p_radius_m in number,
    p_updated_by in number
  );
  procedure get_competition_terms_json(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_default_terms_text in clob,
    o_item_json out clob
  );
  procedure set_competition_terms_text(
    p_competition_id in number,
    p_lang_code in varchar2,
    p_terms_text in clob,
    p_updated_by in number
  );
  procedure get_participant_map_layers_json(
    p_competition_id in number,
    o_items_json out clob
  );
  procedure set_participant_map_layers(
    p_competition_id in number,
    p_layer_codes_json in clob,
    p_updated_by in number
  );
  procedure list_checkpoints_json(p_competition_id in number, o_items_json out clob);
  procedure upsert_access_code(
    p_competition_id in number,
    p_code_type in varchar2,
    p_code in varchar2,
    p_status in varchar2,
    p_expires_at in timestamp,
    p_max_uses in number,
    p_created_by in number,
    o_access_code_id out number
  );
  procedure get_competition_overview_json(p_competition_id in number, o_overview_json out clob);
  procedure get_questions_overview_json(p_competition_id in number, o_questions_json out clob);

  procedure create_checkpoint(
    p_competition_id in number,
    p_title in varchar2,
    p_order_no in number,
    p_location_hint in varchar2,
    p_latitude in number,
    p_longitude in number,
    p_radius_m in number,
    p_location_required in varchar2,
    p_created_by in number,
    o_checkpoint_id out number
  );
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
  procedure soft_delete_checkpoint(p_checkpoint_id in number, p_deleted_by in number);

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
  procedure soft_delete_question(p_question_id in number, p_deleted_by in number);

  procedure replace_question_options_et(
    p_question_id in number,
    p_options_json in clob,
    p_updated_by in number
  );

  procedure replace_question_answers(
    p_question_id in number,
    p_answers_json in clob,
    p_updated_by in number
  );
end pkg_admin_content;
/

create or replace package body pkg_admin_content as
  procedure add_audit(p_entity_type varchar2, p_entity_id number, p_action varchar2, p_by number, p_old clob, p_new clob) is
  begin
    insert into audit_log(audit_id, entity_type, entity_id, action_type, changed_by, changed_at, old_data_json, new_data_json)
    values (seq_audit_log.nextval, p_entity_type, p_entity_id, p_action, p_by, systimestamp, p_old, p_new);
  end;

  function generate_unique_access_code return varchar2 is
    l_code varchar2(20);
    l_exists number;
  begin
    loop
      l_code := to_char(trunc(dbms_random.value(0, 1000000)), 'FM000000');
      select count(*) into l_exists from competition_access_codes c where c.code = l_code;
      exit when l_exists = 0;
    end loop;
    return l_code;
  end;

  procedure list_competitions_json(p_user_id in number, o_items_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'competition_id' value c.competition_id,
        'name' value c.name,
        'status' value c.status,
        'starts_at' value to_char(c.starts_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'ends_at' value to_char(c.ends_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
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

  procedure list_all_competitions_json(o_items_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'competition_id' value c.competition_id,
        'name' value c.name,
        'description' value c.description,
        'status' value c.status,
        'use_location' value nvl(c.use_location, 'N'),
        'show_competitor_location' value nvl(c.show_competitor_location, 'N'),
        'checkpoint_count' value (
          select count(*)
            from checkpoints cp
           where cp.competition_id = c.competition_id
             and (cp.end_date is null or cp.end_date > sysdate)
        ),
        'starts_at' value to_char(c.starts_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'ends_at' value to_char(c.ends_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'created_at' value to_char(c.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'updated_at' value to_char(c.updated_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'organizer_code' value (
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
      'COMPETITION',
      o_competition_id,
      'CREATE',
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
             nvl(c.use_location, 'N'),
             nvl(c.show_competitor_location, 'N'),
             c.radius_m
        into l_name,
             l_description,
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
      competition_id, name, description, status, use_location, show_competitor_location, radius_m, start_date, created_by, created_at
    ) values (
      o_competition_id,
      substr(l_name || ' (koopia)', 1, 255),
      l_description,
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
            checkpoint_id, competition_id, title, order_no, location_hint, latitude, longitude, radius_m, location_required, start_date, created_by, created_at
          ) values (
            l_new_checkpoint_id, o_competition_id, cp.title, cp.order_no, cp.location_hint, cp.latitude, cp.longitude, cp.radius_m, cp.location_required,
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
      'SOFT_DELETE',
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
      to_clob(json_object('starts_at' value to_char(p_starts_at, 'YYYY-MM-DD"T"HH24:MI:SS'), 'ends_at' value to_char(p_ends_at, 'YYYY-MM-DD"T"HH24:MI:SS'))));
  end;

  procedure update_competition_meta(
    p_competition_id in number,
    p_name in varchar2,
    p_description in varchar2,
    p_status in varchar2,
    p_use_location in varchar2,
    p_show_competitor_location in varchar2,
    p_radius_m in number,
    p_updated_by in number
  ) is
    l_name varchar2(255) := trim(p_name);
    l_status varchar2(30) := upper(trim(p_status));
    l_use_location varchar2(1) := upper(trim(nvl(p_use_location, 'N')));
    l_show_competitor_location varchar2(1) := upper(trim(nvl(p_show_competitor_location, 'Y')));
  begin
    if l_name is null then
      raise_application_error(-20120, 'competition name is required');
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
        'status' value l_status,
        'use_location' value l_use_location,
        'show_competitor_location' value l_show_competitor_location,
        'radius_m' value p_radius_m
      )));
  end;

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
      end loop;
    end if;

    if l_selected_count < 1 then
      raise_application_error(-20182, 'at least one layer must be selected');
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

  procedure list_checkpoints_json(p_competition_id in number, o_items_json out clob) is
  begin
    select json_arrayagg(json_object(
      'checkpoint_id' value cp.checkpoint_id,
      'title' value cp.title,
      'order_no' value cp.order_no,
      'location_hint' value cp.location_hint,
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

  procedure upsert_access_code(
    p_competition_id in number, p_code_type in varchar2, p_code in varchar2, p_status in varchar2,
    p_expires_at in timestamp, p_max_uses in number, p_created_by in number, o_access_code_id out number
  ) is
    l_code varchar2(20);
    l_conflict number;
    l_existing_code varchar2(20);
  begin
    l_code := trim(p_code);

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

    if l_code is null then
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
  end;

  procedure get_competition_overview_json(p_competition_id in number, o_overview_json out clob) is
    l_dummy number;
  begin
    begin
      upsert_access_code(p_competition_id, 'COMPETITOR', null, 'ACTIVE', null, null, null, l_dummy);
      upsert_access_code(p_competition_id, 'ORGANIZER', null, 'ACTIVE', null, null, null, l_dummy);
    exception when others then null; end;

    select json_object(
      'competition_id' value c.competition_id,
      'name' value c.name,
      'description' value c.description,
      'status' value c.status,
      'use_location' value c.use_location,
      'show_competitor_location' value c.show_competitor_location,
      'radius_m' value c.radius_m,
      'starts_at' value to_char(c.starts_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
      'ends_at' value to_char(c.ends_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
      'created_at' value to_char(c.created_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
      'updated_at' value to_char(c.updated_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
      'competitor_code' value (select json_object('code' value x.code, 'status' value x.status, 'expires_at' value to_char(x.expires_at, 'YYYY-MM-DD"T"HH24:MI:SS')) from competition_access_codes x where x.competition_id=c.competition_id and x.code_type='COMPETITOR' and (x.end_date is null or x.end_date > sysdate) fetch first 1 row only),
      'organizer_code' value (select json_object('code' value x.code, 'status' value x.status, 'expires_at' value to_char(x.expires_at, 'YYYY-MM-DD"T"HH24:MI:SS')) from competition_access_codes x where x.competition_id=c.competition_id and x.code_type='ORGANIZER' and (x.end_date is null or x.end_date > sysdate) fetch first 1 row only),
      'organizers' value (select json_arrayagg(json_object('user_id' value u.user_id, 'full_name' value u.full_name, 'email' value u.email) returning clob) from competition_organizers co join users u on u.user_id=co.user_id where co.competition_id=c.competition_id and (co.end_date is null or co.end_date > sysdate)),
      'question_count' value (select count(*) from questions q join checkpoints cp on cp.checkpoint_id=q.checkpoint_id where cp.competition_id=c.competition_id and (q.end_date is null or q.end_date > sysdate) and (cp.end_date is null or cp.end_date > sysdate))
      returning clob
    ) into o_overview_json
      from competitions c
     where c.competition_id = p_competition_id
       and (c.end_date is null or c.end_date > sysdate);
  end;

  procedure get_questions_overview_json(p_competition_id in number, o_questions_json out clob) is
  begin
    select json_arrayagg(
      json_object(
        'checkpoint_id' value cp.checkpoint_id,
        'checkpoint_title' value cp.title,
        'checkpoint_order_no' value cp.order_no,
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
        'answers' value (select json_arrayagg(json_object('answer_id' value qa.answer_id,'answer_value' value qa.answer_value,'normalize_mode' value qa.normalize_mode,'is_correct' value qa.is_correct) returning clob) from question_answers qa where qa.question_id=q.question_id and (qa.end_date is null or qa.end_date > sysdate))
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

  procedure create_checkpoint(p_competition_id in number, p_title in varchar2, p_order_no in number, p_location_hint in varchar2, p_latitude in number, p_longitude in number, p_radius_m in number, p_location_required in varchar2, p_created_by in number, o_checkpoint_id out number) is
    l_dummy number;
    l_use_location varchar2(1);
    l_location_required varchar2(1) := upper(trim(nvl(p_location_required, 'N')));
  begin
    if p_competition_id is null or trim(p_title) is null then
      raise_application_error(-20100, 'competition_id and title are required');
    end if;

    begin
      select 1 into l_dummy from checkpoints cp
       where cp.competition_id=p_competition_id and upper(trim(cp.title))=upper(trim(p_title)) and (cp.end_date is null or cp.end_date > sysdate)
       fetch first 1 row only;
      raise_application_error(-20101, 'checkpoint title already exists in this competition');
    exception when no_data_found then null; end;

    select use_location
      into l_use_location
      from competitions
     where competition_id = p_competition_id
       and (end_date is null or end_date > sysdate);
    if l_use_location <> 'Y' then
      l_location_required := 'N';
    end if;
    if l_location_required not in ('Y','N') then
      raise_application_error(-20105, 'invalid location_required');
    end if;

    o_checkpoint_id := seq_checkpoints.nextval;
    insert into checkpoints(checkpoint_id, competition_id, title, order_no, location_hint, latitude, longitude, radius_m, location_required, start_date, created_by, created_at)
    values(o_checkpoint_id, p_competition_id, trim(p_title), p_order_no, p_location_hint, p_latitude, p_longitude, p_radius_m, l_location_required, trunc(sysdate), p_created_by, systimestamp);

    add_audit('CHECKPOINT', o_checkpoint_id, 'CREATE', p_created_by, null,
      to_clob(json_object('competition_id' value p_competition_id,'title' value trim(p_title))));
  end;

  procedure update_checkpoint(p_checkpoint_id in number, p_title in varchar2, p_order_no in number, p_location_hint in varchar2, p_latitude in number, p_longitude in number, p_radius_m in number, p_location_required in varchar2, p_updated_by in number) is
    l_competition_id number;
    l_dummy number;
    l_use_location varchar2(1);
    l_location_required varchar2(1) := upper(trim(nvl(p_location_required, 'N')));
  begin
    if p_checkpoint_id is null or trim(p_title) is null then raise_application_error(-20102, 'checkpoint_id and title are required'); end if;

    select competition_id into l_competition_id from checkpoints where checkpoint_id = p_checkpoint_id and (end_date is null or end_date > sysdate);
    select use_location into l_use_location from competitions where competition_id = l_competition_id and (end_date is null or end_date > sysdate);
    if l_use_location <> 'Y' then
      l_location_required := 'N';
    end if;
    if l_location_required not in ('Y','N') then
      raise_application_error(-20106, 'invalid location_required');
    end if;

    begin
      select 1 into l_dummy from checkpoints cp
       where cp.competition_id=l_competition_id and cp.checkpoint_id<>p_checkpoint_id and upper(trim(cp.title))=upper(trim(p_title)) and (cp.end_date is null or cp.end_date > sysdate)
       fetch first 1 row only;
      raise_application_error(-20103, 'checkpoint title already exists in this competition');
    exception when no_data_found then null; end;

    update checkpoints
       set title=trim(p_title), order_no=p_order_no, location_hint=p_location_hint,
           latitude = p_latitude, longitude = p_longitude, radius_m = p_radius_m, location_required = l_location_required,
           updated_by=p_updated_by, updated_at=systimestamp
     where checkpoint_id = p_checkpoint_id;

    add_audit('CHECKPOINT', p_checkpoint_id, 'UPDATE', p_updated_by, null,
      to_clob(json_object('title' value trim(p_title), 'order_no' value p_order_no, 'location_hint' value p_location_hint, 'latitude' value p_latitude, 'longitude' value p_longitude, 'radius_m' value p_radius_m, 'location_required' value l_location_required)));
  end;

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

    add_audit('QUESTION', o_question_id, 'CREATE', p_created_by, null,
      to_clob(json_object('checkpoint_id' value p_checkpoint_id, 'question_type' value p_question_type, 'question_text' value trim(p_question_text))));
  end;

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
      to_clob(json_object('checkpoint_id' value p_checkpoint_id, 'question_type' value p_question_type, 'question_text' value trim(p_question_text))));
  end;

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

  procedure replace_question_options_et(p_question_id in number, p_options_json in clob, p_updated_by in number) is
    l_arr json_array_t;
    l_obj json_object_t;
    l_keys json_key_list;
    l_option_id number;
    l_text varchar2(4000);
    l_code varchar2(100);
    l_is_correct varchar2(1);
    l_key varchar2(200);
    l_lang varchar2(20);
  begin
    update question_option_texts set end_date = trunc(sysdate), updated_by = p_updated_by, updated_at = systimestamp
     where option_id in (select option_id from question_options where question_id = p_question_id and (end_date is null or end_date > sysdate))
       and (end_date is null or end_date > sysdate);
    update question_options set end_date = trunc(sysdate), updated_by = p_updated_by, updated_at = systimestamp
     where question_id = p_question_id and (end_date is null or end_date > sysdate);

    if p_options_json is null then return; end if;
    l_arr := json_array_t.parse(p_options_json);
    for i in 0 .. l_arr.get_size - 1 loop
      l_obj := treat(l_arr.get(i) as json_object_t);
      l_code := l_obj.get_string('option_code');
      l_text := l_obj.get_string('text_et');
      l_is_correct := case when l_obj.has('is_correct') and upper(l_obj.get_string('is_correct'))='Y' then 'Y' else 'N' end;

      l_option_id := seq_question_options.nextval;
      insert into question_options(option_id, question_id, option_code, order_no, is_correct, start_date, created_by, created_at)
      values(l_option_id, p_question_id, l_code, i+1, l_is_correct, trunc(sysdate), p_updated_by, systimestamp);

      if l_text is not null then
        insert into question_option_texts(question_option_text_id, option_id, lang_code, option_text, start_date, created_by, created_at)
        values(seq_question_option_texts.nextval, l_option_id, 'et', l_text, trunc(sysdate), p_updated_by, systimestamp);
      end if;

      l_keys := l_obj.get_keys;
      for k in 1 .. l_keys.count loop
        l_key := l_keys(k);
        if l_key like 'text\_%' escape '\' and lower(l_key) <> 'text_et' then
          l_lang := lower(substr(l_key, 6));
          l_text := l_obj.get_string(l_key);
          if l_text is not null and trim(l_text) is not null then
            insert into question_option_texts(question_option_text_id, option_id, lang_code, option_text, start_date, created_by, created_at)
            values(seq_question_option_texts.nextval, l_option_id, l_lang, l_text, trunc(sysdate), p_updated_by, systimestamp);
          end if;
        end if;
      end loop;
    end loop;
  end;

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
