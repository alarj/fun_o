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
      raise_application_error(-20070, 'user_id or email is required');
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
      competition_id, name, description, status, start_date, created_by, created_at
    ) values (
      o_competition_id, p_name, p_description, 'DRAFT', trunc(sysdate), p_created_by, systimestamp
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
    l_dummy number;
  begin
    if p_user_id is null or p_access_code is null then
      raise_application_error(-20030, 'user_id and access_code are required');
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
         and (c.expires_at is null or c.expires_at > systimestamp)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and comp.status = 'ACTIVE'
         and (comp.starts_at is null or comp.starts_at <= systimestamp)
         and (comp.ends_at is null or comp.ends_at > systimestamp)
       fetch first 1 row only;
    exception
      when no_data_found then
        raise_application_error(-20031, 'invalid or inactive access code');
    end;

    if l_max_uses is not null and l_used_count >= l_max_uses then
      raise_application_error(-20032, 'access code usage limit reached');
    end if;

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
      status,
      start_date,
      joined_at
    ) values (
      seq_competition_participants.nextval,
      o_competition_id,
      p_user_id,
      l_access_code_id,
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
  begin
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
         and (c.expires_at is null or c.expires_at > systimestamp)
         and c.status = 'ACTIVE'
         and (comp.end_date is null or comp.end_date > sysdate)
         and (comp.ends_at is null or comp.ends_at > systimestamp)
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
      select q.question_type, q.input_type, q.points
        into l_question_type, l_input_type, l_awarded_points
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

      l_normalized_answer := trim(dbms_lob.substr(p_answer_text, 4000, 1));
      if l_input_type = 'NUMERIC' then
        l_normalized_answer := regexp_replace(l_normalized_answer, '[^0-9\-]', '');
      end if;

      select count(*)
        into l_correct_count
        from question_answers qa
       where qa.question_id = p_question_id
         and qa.is_correct = 'Y'
         and (qa.end_date is null or qa.end_date > sysdate)
         and (
              (qa.normalize_mode = 'EXACT' and qa.answer_value = l_normalized_answer)
           or (qa.normalize_mode = 'TRIM_UPPER' and upper(trim(qa.answer_value)) = upper(trim(l_normalized_answer)))
           or (qa.normalize_mode = 'LOWER_TRIM' and lower(trim(qa.answer_value)) = lower(trim(l_normalized_answer)))
           or (qa.normalize_mode = 'NUMERIC' and regexp_replace(trim(qa.answer_value), '[^0-9\-]', '') = regexp_replace(trim(l_normalized_answer), '[^0-9\-]', ''))
         );

      if l_correct_count > 0 then
        l_is_correct := 'Y';
      end if;
    end if;

    if l_is_correct = 'N' then
      l_awarded_points := 0;
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
      evaluated_at,
      start_date
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
      systimestamp,
      trunc(sysdate)
    );

    o_is_correct := l_is_correct;
    o_awarded_points := nvl(l_awarded_points, 0);

    select nvl(sum(nvl(s.awarded_points, 0)), 0)
      into o_total_score
      from submissions s
     where s.competition_id = p_competition_id
       and s.user_id = p_user_id
       and (s.end_date is null or s.end_date > sysdate);
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
       and s.user_id = p_user_id
       and (s.end_date is null or s.end_date > sysdate);
  end;

  procedure get_competition_leaderboard(
    p_competition_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'user_id' value x.user_id,
               'score' value x.score
             ) returning clob
           )
      into o_items_json
      from (
        select s.user_id,
               nvl(sum(nvl(s.awarded_points, 0)), 0) as score
          from submissions s
         where s.competition_id = p_competition_id
           and (s.end_date is null or s.end_date > sysdate)
         group by s.user_id
         order by score desc, s.user_id
      ) x;

    if o_items_json is null then
      o_items_json := '[]';
    end if;
  end;
end pkg_results;
/

create or replace package pkg_competitor as
  procedure list_my_competitions_json(
    p_user_id in number,
    o_items_json out clob
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
end pkg_competitor;
/

create or replace package body pkg_competitor as
  procedure list_my_competitions_json(
    p_user_id in number,
    o_items_json out clob
  ) is
  begin
    select json_arrayagg(
             json_object(
               'competition_id' value x.competition_id,
               'name' value x.name,
               'starts_at' value case when x.starts_at is not null then to_char(x.starts_at, 'YYYY-MM-DD"T"HH24:MI:SS') else null end,
               'ends_at' value case when x.ends_at is not null then to_char(x.ends_at, 'YYYY-MM-DD"T"HH24:MI:SS') else null end,
               'use_location' value nvl(x.use_location, 'N')
             ) returning clob
           )
      into o_items_json
      from (
        select c.competition_id,
               c.name,
               c.starts_at,
               c.ends_at,
               c.use_location
         from competition_participants cp
          join competitions c
            on c.competition_id = cp.competition_id
         where cp.user_id = p_user_id
           and (cp.end_date is null or cp.end_date > sysdate)
           and (c.end_date is null or c.end_date > sysdate)
           and c.status = 'ACTIVE'
           and (c.starts_at is null or c.starts_at <= systimestamp)
           and (c.ends_at is null or c.ends_at > systimestamp)
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
                and (s.end_date is null or s.end_date > sysdate)
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
                      and (s.end_date is null or s.end_date > sysdate)
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
end pkg_competitor;
/

create or replace package pkg_admin_content as
  procedure list_competitions_json(p_user_id in number, o_items_json out clob);
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
    p_radius_m in number,
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
    p_radius_m in number,
    p_updated_by in number
  ) is
    l_name varchar2(255) := trim(p_name);
    l_status varchar2(30) := upper(trim(p_status));
    l_use_location varchar2(1) := upper(trim(nvl(p_use_location, 'N')));
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
    if p_radius_m is not null and p_radius_m <= 0 then
      raise_application_error(-20123, 'radius_m must be > 0');
    end if;

    update competitions
       set name = l_name,
           description = p_description,
           status = l_status,
           use_location = l_use_location,
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
        'radius_m' value p_radius_m
      )));
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
      ) returning clob
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
    p_input_pattern in varchar2, p_points in number, p_lang_code in varchar2,
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
    insert into questions(question_id, checkpoint_id, question_type, input_type, input_max_length, input_pattern, points, status, start_date, created_by, created_at)
    values(o_question_id, p_checkpoint_id, p_question_type, p_input_type, p_input_max_length, p_input_pattern, nvl(p_points,0), 'ACTIVE', trunc(sysdate), p_created_by, systimestamp);

    insert into question_texts(question_text_id, question_id, lang_code, question_text, start_date, created_by, created_at)
    values(seq_question_texts.nextval, o_question_id, l_lang, trim(p_question_text), trunc(sysdate), p_created_by, systimestamp);

    add_audit('QUESTION', o_question_id, 'CREATE', p_created_by, null,
      to_clob(json_object('checkpoint_id' value p_checkpoint_id, 'question_type' value p_question_type, 'question_text' value trim(p_question_text))));
  end;

  procedure update_question(
    p_question_id in number, p_checkpoint_id in number, p_question_type in varchar2, p_input_type in varchar2,
    p_input_max_length in number, p_input_pattern in varchar2, p_points in number,
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
           input_max_length = p_input_max_length, input_pattern = p_input_pattern, points = nvl(p_points,0),
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

