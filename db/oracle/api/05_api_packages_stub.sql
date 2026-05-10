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
       where c.code = p_access_code
         and (c.end_date is null or c.end_date > sysdate)
         and (c.expires_at is null or c.expires_at > systimestamp)
         and c.status = 'ACTIVE'
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
end pkg_competitions;
/

create or replace package pkg_questions as
  procedure create_question(
    p_checkpoint_id in number,
    p_question_text in varchar2,
    p_question_type in varchar2,
    p_points in number,
    p_order_no in number,
    p_created_by in number,
    o_question_id out number
  );
end pkg_questions;
/

create or replace package body pkg_questions as
  procedure create_question(
    p_checkpoint_id in number,
    p_question_text in varchar2,
    p_question_type in varchar2,
    p_points in number,
    p_order_no in number,
    p_created_by in number,
    o_question_id out number
  ) is
    l_dummy number;
  begin
    if p_checkpoint_id is null or p_question_text is null or p_question_type is null or p_order_no is null then
      raise_application_error(-20050, 'checkpoint_id, question_text, question_type and order_no are required');
    end if;

    begin
      select 1
        into l_dummy
        from questions q
       where q.checkpoint_id = p_checkpoint_id
         and q.order_no = p_order_no
         and (q.end_date is null or q.end_date > sysdate)
       fetch first 1 row only;

      raise_application_error(-20051, 'active question order already exists in checkpoint');
    exception
      when no_data_found then
        null;
    end;

    o_question_id := seq_questions.nextval;
    insert into questions (
      question_id,
      checkpoint_id,
      question_text,
      question_type,
      points,
      order_no,
      status,
      start_date,
      created_by,
      created_at
    ) values (
      o_question_id,
      p_checkpoint_id,
      p_question_text,
      p_question_type,
      nvl(p_points, 0),
      p_order_no,
      'ACTIVE',
      trunc(sysdate),
      p_created_by,
      systimestamp
    );
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
    o_submission_id out number
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
    o_submission_id out number
  ) is
    l_dummy number;
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

    o_submission_id := seq_submissions.nextval;
    insert into submissions (
      submission_id,
      competition_id,
      checkpoint_id,
      question_id,
      user_id,
      answer_text,
      submitted_at,
      start_date
    ) values (
      o_submission_id,
      p_competition_id,
      p_checkpoint_id,
      p_question_id,
      p_user_id,
      p_answer_text,
      systimestamp,
      trunc(sysdate)
    );
  end;
end pkg_submissions;
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
