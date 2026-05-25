-- testing/sql/02_create_loadtest_competition_no_location.sql
-- Run as FUNO_APP
-- Creates:
--  - 1 non-location ACTIVE competition (use_location='N')
--  - 1 competitor + 1 organizer access code
--  - 50 checkpoints (with coordinates for map endpoint compatibility)
--  - 1 TEXT question per checkpoint: "Kuidas läheb?" (1 point)
--  - accepted answer: "OK"
--  - links existing users T001..T200 as ACTIVE participants

set serveroutput on;

declare
  c_user_count            constant pls_integer := 200;
  c_checkpoint_count      constant pls_integer := 50;
  -- Change when needed
  c_test_duration_min     constant number := 240;

  v_competition_id        number;
  v_competitor_code       varchar2(20);
  v_organizer_code        varchar2(20);
  v_start_ts              timestamp;
  v_end_ts                timestamp;

  v_cp_id                 number;
  v_q_id                  number;
  v_qt_id                 number;
  v_qa_id                 number;
  v_terms_id              number;
  v_terms_text_id         number;

  v_user_id               number;

  function make_unique_code return varchar2 is
    v_code varchar2(20);
    v_dummy number;
  begin
    while true loop
      v_code := lpad(to_char(trunc(dbms_random.value(0, 1000000))), 6, '0');
      begin
        select 1 into v_dummy
          from competition_access_codes
         where code = v_code;
      exception
        when no_data_found then
          return v_code;
      end;
    end loop;
    return v_code;
  end;
begin
  v_start_ts := systimestamp;
  v_end_ts := v_start_ts + numtodsinterval(c_test_duration_min, 'MINUTE');

  v_competition_id := seq_competitions.nextval;
  insert into competitions (
    competition_id,
    name,
    description,
    status,
    use_location,
    show_competitor_location,
    radius_m,
    starts_at,
    ends_at,
    start_date,
    end_date,
    created_at,
    updated_at
  ) values (
    v_competition_id,
    'Loadtest NOLOC ' || to_char(v_start_ts, 'YYYY-MM-DD HH24:MI:SS'),
    'Auto load-test competition without location requirement (200 users, 50 checkpoints)', -- NOSONAR: S1192 repeated literal accepted for script readability/stability
    'ACTIVE',
    'N',
    'N',
    null,
    v_start_ts,
    v_end_ts,
    trunc(sysdate),
    null,
    systimestamp,
    systimestamp
  );

  v_competitor_code := make_unique_code();
  v_organizer_code := make_unique_code();

  insert into competition_access_codes (
    access_code_id,
    competition_id,
    code,
    code_type,
    status,
    expires_at,
    max_uses,
    used_count,
    start_date,
    end_date,
    created_at
  ) values (
    seq_competition_access_codes.nextval,
    v_competition_id,
    v_competitor_code,
    'COMPETITOR',
    'ACTIVE',
    v_end_ts,
    null,
    0,
    trunc(sysdate),
    null,
    systimestamp
  );

  v_terms_id := seq_competition_terms.nextval;
  insert into competition_terms (
    terms_id,
    competition_id,
    version_no,
    status,
    start_date,
    end_date,
    created_at,
    updated_at
  ) values (
    v_terms_id,
    v_competition_id,
    1,
    'ACTIVE',
    trunc(sysdate),
    null,
    systimestamp,
    systimestamp
  );

  v_terms_text_id := seq_competition_terms_texts.nextval;
  insert into competition_terms_texts (
    terms_text_id,
    terms_id,
    lang_code,
    terms_text,
    start_date,
    end_date,
    created_at,
    updated_at
  ) values (
    v_terms_text_id,
    v_terms_id,
    'et',
    'Loadtest no-location terms',
    trunc(sysdate),
    null,
    systimestamp,
    systimestamp
  );

  insert into competition_access_codes (
    access_code_id,
    competition_id,
    code,
    code_type,
    status,
    expires_at,
    max_uses,
    used_count,
    start_date,
    end_date,
    created_at
  ) values (
    seq_competition_access_codes.nextval,
    v_competition_id,
    v_organizer_code,
    'ORGANIZER',
    'ACTIVE',
    v_end_ts,
    null,
    0,
    trunc(sysdate),
    null,
    systimestamp
  );

  for i in 1 .. c_checkpoint_count loop
    v_cp_id := seq_checkpoints.nextval;
    insert into checkpoints (
      checkpoint_id,
      competition_id,
      title,
      order_no,
      location_hint,
      latitude,
      longitude,
      radius_m,
      location_required,
      start_date,
      end_date,
      created_at,
      updated_at
    ) values (
      v_cp_id,
      v_competition_id,
      'KP ' || lpad(to_char(i), 2, '0'),
      i,
      'Loadtest checkpoint ' || i,
      null,
      null,
      null,
      'N',
      trunc(sysdate),
      null,
      systimestamp,
      systimestamp
    );

    v_q_id := seq_questions.nextval;
    insert into questions (
      question_id,
      checkpoint_id,
      question_type,
      input_type,
      input_max_length,
      points,
      status,
      start_date,
      end_date,
      created_at,
      updated_at
    ) values (
      v_q_id,
      v_cp_id,
      'TEXT',
      'TEXT',
      10,
      1,
      'ACTIVE',
      trunc(sysdate),
      null,
      systimestamp,
      systimestamp
    );

    v_qt_id := seq_question_texts.nextval;
    insert into question_texts (
      question_text_id,
      question_id,
      lang_code,
      question_text,
      start_date,
      end_date,
      created_at,
      updated_at
    ) values (
      v_qt_id,
      v_q_id,
      'et',
      unistr('Kuidas l\00E4heb?'),
      trunc(sysdate),
      null,
      systimestamp,
      systimestamp
    );

    v_qa_id := seq_question_answers.nextval;
    insert into question_answers (
      answer_id,
      question_id,
      answer_value,
      is_correct,
      normalize_mode,
      start_date,
      end_date,
      created_at,
      updated_at
    ) values (
      v_qa_id,
      v_q_id,
      'OK',
      'Y',
      'LOWER_TRIM',
      trunc(sysdate),
      null,
      systimestamp,
      systimestamp
    );
  end loop;

  for i in 1 .. c_user_count loop
    begin
      select u.user_id
        into v_user_id
        from users u -- NOSONAR: S1192 repeated literal accepted for script readability/stability
       where lower(u.email) = lower('t' || lpad(to_char(i), 3, '0') || '@funo.local')
         and u.end_date is null;
    exception
      when no_data_found then
        v_user_id := seq_users.nextval;
        insert into users (
          user_id,
          email,
          full_name,
          google_sub,
          auth_type,
          start_date,
          end_date,
          created_at,
          updated_at
        ) values (
          v_user_id,
          't' || lpad(to_char(i), 3, '0') || '@funo.local',
          'T' || lpad(to_char(i), 3, '0'),
          'dev:t' || lpad(to_char(i), 3, '0') || '@funo.local',
          'ANON',
          trunc(sysdate),
          null,
          systimestamp,
          systimestamp
        );
    end;

    merge into competition_participants cp
    using (
      select v_competition_id as competition_id,
             v_user_id as user_id,
             ('T' || lpad(to_char(i), 3, '0')) as alias_display,
             ('t' || lpad(to_char(i), 3, '0') || '@funo.local') as contact_email
        from dual
    ) s
    on (
      cp.competition_id = s.competition_id
      and cp.user_id = s.user_id
      and cp.end_date is null
    )
    when matched then
      update set
        cp.status = 'ACTIVE',
        cp.alias_display = s.alias_display,
        cp.contact_email = s.contact_email,
        cp.terms_id = v_terms_id,
        cp.terms_lang_code = 'et',
        cp.terms_accepted_at = systimestamp,
        cp.start_date = trunc(sysdate),
        cp.joined_at = systimestamp
    when not matched then
      insert (
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
        end_date,
        joined_at
      ) values (
        seq_competition_participants.nextval,
        s.competition_id,
        s.user_id,
        null,
        s.alias_display,
        s.contact_email,
        v_terms_id,
        'et',
        systimestamp,
        'ACTIVE',
        trunc(sysdate),
        null,
        systimestamp
      );
  end loop;

  commit;

  dbms_output.put_line('Competition created: competition_id=' || v_competition_id);
  dbms_output.put_line('Competitor access code: ' || v_competitor_code);
  dbms_output.put_line('Organizer access code:  ' || v_organizer_code);
  dbms_output.put_line('Users linked: T001..T' || lpad(to_char(c_user_count), 3, '0'));
  dbms_output.put_line('Mode: NO LOCATION');
  dbms_output.put_line('Duration (min): ' || c_test_duration_min);
end;
/
