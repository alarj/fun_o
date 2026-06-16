-- 04_app_schema_ddl.sql
-- Run as FUNO_APP

-- Sequences
create sequence seq_users start with 1 increment by 1;
create sequence seq_roles start with 1 increment by 1;
create sequence seq_user_roles start with 1 increment by 1;
create sequence seq_competitions start with 1 increment by 1;
create sequence seq_competition_access_codes start with 1 increment by 1;
create sequence seq_competition_organizers start with 1 increment by 1;
create sequence seq_competition_participants start with 1 increment by 1;
create sequence seq_competition_part_map_layers start with 1 increment by 1;
create sequence seq_competition_map_overlays start with 1 increment by 1;
create sequence seq_competition_terms start with 1 increment by 1;
create sequence seq_competition_terms_texts start with 1 increment by 1;
create sequence seq_checkpoints start with 1 increment by 1;
create sequence seq_questions start with 1 increment by 1;
create sequence seq_question_texts start with 1 increment by 1;
create sequence seq_question_options start with 1 increment by 1;
create sequence seq_question_option_texts start with 1 increment by 1;
create sequence seq_question_answers start with 1 increment by 1;
create sequence seq_submissions start with 1 increment by 1;
create sequence seq_materials start with 1 increment by 1;
create sequence seq_audit_log start with 1 increment by 1;

create table users (
  user_id number primary key,
  email varchar2(320),
  full_name varchar2(200),
  google_sub varchar2(255),
  auth_type varchar2(20) default 'ANON' not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint chk_users_dates check (end_date is null or end_date >= start_date),
  constraint chk_users_auth_type check (auth_type in ('ANON', 'GOOGLE'))
);

create table roles (
  role_id number primary key,
  role_code varchar2(50) not null,
  role_name varchar2(120) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  constraint chk_roles_dates check (end_date is null or end_date >= start_date)
);

create table user_roles (
  user_role_id number primary key,
  user_id number not null,
  role_id number not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  assigned_by number,
  assigned_at timestamp default systimestamp not null,
  constraint fk_ur_user foreign key (user_id) references users(user_id),
  constraint fk_ur_role foreign key (role_id) references roles(role_id),
  constraint fk_ur_assigned_by foreign key (assigned_by) references users(user_id),
  constraint chk_user_roles_dates check (end_date is null or end_date >= start_date)
);

create table competitions (
  competition_id number primary key,
  name varchar2(200) not null,
  description varchar2(2000),
  type varchar2(1) default 'R' not null,
  status varchar2(30) not null,
  use_location varchar2(1) default 'N' not null,
  show_competitor_location varchar2(1) default 'Y' not null,
  radius_m number,
  starts_at timestamp,
  mass_start_at timestamp,
  ends_at timestamp,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_comp_created_by foreign key (created_by) references users(user_id),
  constraint fk_comp_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_comp_dates check (end_date is null or end_date >= start_date),
  constraint chk_comp_type check (type in ('R','S')),
  constraint chk_comp_use_location check (use_location in ('Y','N')),
  constraint chk_comp_show_comp_loc check (show_competitor_location in ('Y','N')),
  constraint chk_comp_radius check (radius_m is null or radius_m > 0)
);

create table competition_declinations (
  competition_id number primary key,
  declination number(10,4),
  last_updated timestamp default systimestamp not null,
  constraint fk_comp_declinations_comp foreign key (competition_id) references competitions(competition_id)
);

create table app_settings (
  setting_key varchar2(100) primary key,
  setting_value varchar2(4000),
  setting_type varchar2(20),
  description varchar2(1000),
  updated_at timestamp,
  updated_by number,
  constraint chk_app_settings_type check (setting_type in ('STRING', 'NUMBER', 'BOOLEAN', 'JSON'))
);

create table competition_routes (
  competition_id number primary key,
  calc_status varchar2(20),
  route_length_m number,
  algorithm_code varchar2(30),
  included_checkpoint_count number,
  route_order_json clob,
  calculated_source_hash varchar2(64),
  requested_at timestamp,
  started_at timestamp,
  calculated_at timestamp,
  calculation_duration_ms number,
  attempt_count number default 0,
  error_message varchar2(2000),
  created_at timestamp default systimestamp,
  updated_at timestamp default systimestamp,
  constraint fk_comp_routes_comp foreign key (competition_id) references competitions(competition_id),
  constraint chk_comp_routes_status check (calc_status in ('PENDING', 'PROCESSING', 'READY', 'FAILED')),
  constraint chk_comp_routes_attempt_count check (attempt_count >= 0),
  constraint chk_comp_routes_duration check (calculation_duration_ms is null or calculation_duration_ms >= 0),
  constraint chk_comp_routes_json check (route_order_json is json)
);

create table competition_access_codes (
  access_code_id number primary key,
  competition_id number not null,
  code varchar2(20) not null,
  status varchar2(30) not null,
  expires_at timestamp,
  max_uses number,
  used_count number default 0 not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  created_at timestamp default systimestamp not null,
  constraint fk_cac_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_cac_created_by foreign key (created_by) references users(user_id),
  constraint chk_cac_dates check (end_date is null or end_date >= start_date)
);

create table competition_organizers (
  competition_organizer_id number primary key,
  competition_id number not null,
  user_id number not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  assigned_by number,
  assigned_at timestamp default systimestamp not null,
  constraint fk_co_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_co_user foreign key (user_id) references users(user_id),
  constraint fk_co_assigned_by foreign key (assigned_by) references users(user_id),
  constraint chk_co_dates check (end_date is null or end_date >= start_date)
);

create table competition_terms (
  terms_id number primary key,
  competition_id number not null,
  version_no number not null,
  status varchar2(30) default 'ACTIVE' not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_ct_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_ct_created_by foreign key (created_by) references users(user_id),
  constraint fk_ct_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_ct_dates check (end_date is null or end_date >= start_date),
  constraint chk_ct_version check (version_no > 0),
  constraint chk_ct_status check (status in ('ACTIVE', 'INACTIVE'))
);

create table competition_terms_texts (
  terms_text_id number primary key,
  terms_id number not null,
  lang_code varchar2(10) not null,
  terms_text clob not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_ctt_terms foreign key (terms_id) references competition_terms(terms_id),
  constraint fk_ctt_created_by foreign key (created_by) references users(user_id),
  constraint fk_ctt_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_ctt_dates check (end_date is null or end_date >= start_date),
  constraint chk_ctt_lang check (regexp_like(lang_code, '^[a-z]{2}(-[A-Z]{2})?$')) -- NOSONAR: S1192 repeated literal accepted for script readability/stability
);

create table competition_participants (
  competition_participant_id number primary key,
  competition_id number not null,
  user_id number not null,
  access_code_id number,
  alias_display varchar2(120) not null,
  contact_email varchar2(320),
  terms_id number not null,
  terms_lang_code varchar2(10) not null,
  terms_accepted_at timestamp not null,
  status varchar2(30) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  joined_at timestamp default systimestamp not null,
  constraint fk_cp_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_cp_user foreign key (user_id) references users(user_id),
  constraint fk_cp_code foreign key (access_code_id) references competition_access_codes(access_code_id),
  constraint fk_cp_terms foreign key (terms_id) references competition_terms(terms_id),
  constraint chk_cp_dates check (end_date is null or end_date >= start_date),
  constraint chk_cp_alias_not_blank check (trim(alias_display) is not null),
  constraint chk_cp_terms_lang check (regexp_like(terms_lang_code, '^[a-z]{2}(-[A-Z]{2})?$')),
  constraint chk_cp_contact_email check (
    contact_email is null
    or regexp_like(contact_email, '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
  )
);

create table competition_participant_map_layers (
  competition_participant_map_layer_id number primary key,
  competition_id number not null,
  layer_code varchar2(100) not null,
  start_date date default cast((systimestamp at time zone 'UTC') as date) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_cpml_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_cpml_created_by foreign key (created_by) references users(user_id),
  constraint fk_cpml_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_cpml_dates check (end_date is null or end_date >= start_date)
);

create table competition_map_overlays (
  overlay_id number primary key,
  competition_id number not null,
  display_name varchar2(200) not null,
  attribution varchar2(1000),
  image_file_name varchar2(255) not null,
  world_file_name varchar2(255) not null,
  image_mime_type varchar2(100) not null,
  image_size_bytes number not null,
  storage_rel_path varchar2(1000) not null,
  processing_status varchar2(20) default 'UPLOADED' not null,
  processing_error varchar2(2000),
  tile_storage_rel_path varchar2(1000),
  tile_min_zoom number,
  tile_max_zoom number,
  tiles_generated_at timestamp,
  crs_code varchar2(32) not null,
  width_px number not null,
  height_px number not null,
  pixel_size_x number not null,
  pixel_size_y number not null,
  top_left_x number not null,
  top_left_y number not null,
  min_x number not null,
  min_y number not null,
  max_x number not null,
  max_y number not null,
  start_date date default cast((systimestamp at time zone 'UTC') as date) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_cmo_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_cmo_created_by foreign key (created_by) references users(user_id),
  constraint fk_cmo_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_cmo_dates check (end_date is null or end_date >= start_date),
  constraint chk_cmo_crs check (upper(crs_code) = 'EPSG:3301'),
  constraint chk_cmo_processing_status check (processing_status in ('UPLOADED', 'PROCESSING', 'READY', 'FAILED')),
  constraint chk_cmo_image_size check (image_size_bytes > 0),
  constraint chk_cmo_dimensions check (width_px > 0 and height_px > 0)
);

create table checkpoints (
  checkpoint_id number primary key,
  competition_id number not null,
  title varchar2(200) not null,
  checkpoint_type varchar2(10),
  checkpoint_interaction varchar2(20) default 'QUESTION' not null,
  order_no number,
  location_hint varchar2(500),
  latitude number(9,6),
  longitude number(9,6),
  radius_m number,
  location_required varchar2(1) default 'N' not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_chk_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_chk_created_by foreign key (created_by) references users(user_id),
  constraint fk_chk_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_checkpoints_dates check (end_date is null or end_date >= start_date),
  constraint chk_cp_lat check (latitude is null or (latitude between -90 and 90)),
  constraint chk_cp_lon check (longitude is null or (longitude between -180 and 180)),
  constraint chk_cp_radius check (radius_m is null or radius_m > 0),
  constraint chk_cp_location_required check (location_required in ('Y','N')),
  constraint chk_checkpoints_type check (checkpoint_type is null or upper(trim(checkpoint_type)) in ('NORMAL','START','FINISH')), -- NOSONAR: explicit DDL literals are preferred here over indirection
  constraint chk_checkpoints_interaction check (upper(trim(checkpoint_interaction)) in ('QUESTION','CHECK_ONLY','MASS_START'))
);

create table questions (
  question_id number primary key,
  checkpoint_id number not null,
  question_type varchar2(30) not null,
  input_type varchar2(30),
  input_max_length number,
  input_pattern varchar2(300),
  placeholder_key varchar2(300),
  help_text_key varchar2(300),
  points number default 0 not null,
  wrong_points number default 0 not null,
  status varchar2(30) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_q_chk foreign key (checkpoint_id) references checkpoints(checkpoint_id),
  constraint fk_q_created_by foreign key (created_by) references users(user_id),
  constraint fk_q_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_questions_dates check (end_date is null or end_date >= start_date),
  constraint chk_question_type check (question_type in ('TEXT', 'SINGLE_CHOICE')),
  constraint chk_input_type check (input_type is null or input_type in ('TEXT', 'NUMERIC')),
  constraint chk_input_max_length check (input_max_length is null or (input_max_length > 0 and input_max_length <= 4000))
);

create table question_texts (
  question_text_id number primary key,
  question_id number not null,
  lang_code varchar2(10) not null,
  question_text varchar2(4000) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_qt_question foreign key (question_id) references questions(question_id),
  constraint fk_qt_created_by foreign key (created_by) references users(user_id),
  constraint fk_qt_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_qt_dates check (end_date is null or end_date >= start_date),
  constraint chk_qt_lang check (regexp_like(lang_code, '^[a-z]{2}(-[A-Z]{2})?$'))
);

create table question_options (
  option_id number primary key,
  question_id number not null,
  option_code varchar2(80) not null,
  order_no number not null,
  is_correct varchar2(1) default 'N' not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_qo_question foreign key (question_id) references questions(question_id),
  constraint fk_qo_created_by foreign key (created_by) references users(user_id),
  constraint fk_qo_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_qo_dates check (end_date is null or end_date >= start_date),
  constraint chk_qo_is_correct check (is_correct in ('Y', 'N'))
);

create table question_option_texts (
  question_option_text_id number primary key,
  option_id number not null,
  lang_code varchar2(10) not null,
  option_text varchar2(4000) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_qot_option foreign key (option_id) references question_options(option_id),
  constraint fk_qot_created_by foreign key (created_by) references users(user_id),
  constraint fk_qot_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_qot_dates check (end_date is null or end_date >= start_date),
  constraint chk_qot_lang check (regexp_like(lang_code, '^[a-z]{2}(-[A-Z]{2})?$'))
);

create table question_answers (
  answer_id number primary key,
  question_id number not null,
  answer_value varchar2(4000) not null,
  is_correct varchar2(1) default 'Y' not null,
  normalize_mode varchar2(30) default 'EXACT' not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_qa_question foreign key (question_id) references questions(question_id),
  constraint fk_qa_created_by foreign key (created_by) references users(user_id),
  constraint fk_qa_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_qa_dates check (end_date is null or end_date >= start_date),
  constraint chk_qa_is_correct check (is_correct in ('Y', 'N')),
  constraint chk_qa_normalize_mode check (normalize_mode in ('EXACT', 'TRIM_UPPER', 'LOWER_TRIM', 'NUMERIC'))
);

create table submissions (
  submission_id number primary key,
  competition_id number not null,
  checkpoint_id number not null,
  question_id number not null,
  user_id number not null,
  answer_text varchar2(4000),
  selected_option_id number,
  latitude number(9,6),
  longitude number(9,6),
  radius_m number,
  awarded_points number,
  is_correct varchar2(1),
  submitted_at timestamp default systimestamp not null,
  evaluated_by number,
  evaluated_at timestamp,
  constraint fk_s_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_s_chk foreign key (checkpoint_id) references checkpoints(checkpoint_id),
  constraint fk_s_q foreign key (question_id) references questions(question_id),
  constraint fk_s_selected_option foreign key (selected_option_id) references question_options(option_id),
  constraint fk_s_user foreign key (user_id) references users(user_id),
  constraint fk_s_eval_by foreign key (evaluated_by) references users(user_id)
);

create table submission_events (
  submission_event_id number primary key,
  competition_id number not null,
  checkpoint_id number not null,
  user_id number not null,
  event varchar2(20) not null,
  latitude number(9,6),
  longitude number(9,6),
  radius_m number,
  awarded_points number,
  submitted_at timestamp default systimestamp not null,
  evaluated_by number,
  evaluated_at timestamp,
  constraint fk_se_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_se_chk foreign key (checkpoint_id) references checkpoints(checkpoint_id),
  constraint fk_se_user foreign key (user_id) references users(user_id),
  constraint fk_se_eval_by foreign key (evaluated_by) references users(user_id),
  constraint chk_submission_events_event check (event in ('CHECK_ONLY', 'MASS_START'))
);

create or replace view submissions_v as
  select s.submission_id as id,
         s.submission_id,
         cast(null as number) as submission_event_id,
         'SUBMISSION' as submission_source,
         'QUESTION' as event,
         s.competition_id,
         s.checkpoint_id,
         s.question_id,
         s.user_id,
         s.answer_text,
         s.selected_option_id,
         s.latitude,
         s.longitude,
         s.radius_m,
         s.awarded_points,
         s.is_correct,
         s.submitted_at,
         s.evaluated_by,
         s.evaluated_at
    from submissions s
  union all
  select se.submission_event_id as id,
         cast(null as number) as submission_id,
         se.submission_event_id,
         'EVENT' as submission_source,
         se.event,
         se.competition_id,
         se.checkpoint_id,
         cast(null as number) as question_id,
         se.user_id,
         cast(null as varchar2(4000)) as answer_text,
         cast(null as number) as selected_option_id,
         se.latitude,
         se.longitude,
         se.radius_m,
         se.awarded_points,
         'Y' as is_correct,
         se.submitted_at,
         se.evaluated_by,
         se.evaluated_at
    from submission_events se;

create table materials (
  material_id number primary key,
  competition_id number,
  checkpoint_id number,
  title varchar2(200) not null,
  material_type varchar2(30) not null,
  uri varchar2(2000) not null,
  visibility varchar2(30) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_m_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_m_chk foreign key (checkpoint_id) references checkpoints(checkpoint_id),
  constraint fk_m_created_by foreign key (created_by) references users(user_id),
  constraint fk_m_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_materials_dates check (end_date is null or end_date >= start_date),
  constraint chk_material_owner check (competition_id is not null or checkpoint_id is not null)
);

create table audit_log (
  audit_id number primary key,
  entity_type varchar2(100) not null,
  entity_id number not null,
  action_type varchar2(30) not null,
  changed_by number,
  changed_at timestamp default systimestamp not null,
  old_data_json clob,
  new_data_json clob,
  constraint fk_audit_changed_by foreign key (changed_by) references users(user_id)
);

-- Baseline uniqueness
create unique index ux_users_email on users (lower(email));
create unique index ux_users_google_sub on users (google_sub);
create unique index ux_roles_code on roles (role_code);

-- Active-record uniqueness via index:
-- Oracle function-based indexes cannot use SYSDATE (ORA-01743).
-- Therefore index-level uniqueness is enforced for open-ended rows (end_date IS NULL).
-- Additional business-rule check for "end_date > SYSDATE" must be enforced in PL/SQL procedures.
create unique index ux_active_access_code on competition_access_codes (
  case when end_date is null then code end
);

create unique index ux_active_comp_participant_comp_user on competition_participants (
  case when end_date is null then competition_id end,
  case when end_date is null then user_id end
);
create unique index ux_active_cpml_comp_layer on competition_participant_map_layers (
  case when end_date is null then competition_id end,
  case when end_date is null then lower(layer_code) end
);

create unique index ux_active_cmo_comp on competition_map_overlays (
  case when end_date is null then competition_id end
);

create index ix_comp_routes_status_requested on competition_routes (
  calc_status,
  requested_at
);

create unique index ux_active_cp_alias_ci on competition_participants (
  case when end_date is null then competition_id end,
  case when end_date is null then nlssort(trim(alias_display), 'NLS_SORT=BINARY_CI') end
);

create unique index ux_active_comp_terms_version on competition_terms (
  case when end_date is null then competition_id end,
  case when end_date is null then version_no end
);

create unique index ux_active_comp_terms_text_lang on competition_terms_texts (
  case when end_date is null then terms_id end,
  case when end_date is null then lower(lang_code) end
);

create unique index ux_active_comp_organizer on competition_organizers (
  case when end_date is null then competition_id end,
  case when end_date is null then user_id end
);

create unique index ux_active_cp_order on checkpoints (
  case when end_date is null and order_no is not null then competition_id end,
  case when end_date is null and order_no is not null then order_no end
);

create unique index ux_active_cp_special_type on checkpoints (
  case
    when end_date is null
     and upper(nvl(trim(checkpoint_type), 'NORMAL')) in ('START', 'FINISH')
    then competition_id
  end,
  case
    when end_date is null
     and upper(nvl(trim(checkpoint_type), 'NORMAL')) in ('START', 'FINISH')
    then upper(nvl(trim(checkpoint_type), 'NORMAL'))
  end
);

create unique index ux_active_qt_lang on question_texts (
  case when end_date is null then question_id end,
  case when end_date is null then lower(lang_code) end
);

create unique index ux_active_qo_code on question_options (
  case when end_date is null then question_id end,
  case when end_date is null then option_code end
);

create unique index ux_active_qo_order on question_options (
  case when end_date is null then question_id end,
  case when end_date is null then order_no end
);

create unique index ux_active_qot_lang on question_option_texts (
  case when end_date is null then option_id end,
  case when end_date is null then lower(lang_code) end
);

create unique index ux_submissions_comp_user_cp_q on submissions (
  competition_id,
  user_id,
  checkpoint_id,
  question_id
);

create unique index ux_submission_events_comp_user_cp_evt on submission_events (
  competition_id,
  user_id,
  checkpoint_id,
  event
);

-- Seed roles
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'SYSTEM_OWNER', 'System Owner', trunc(sysdate));
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'ORGANIZER', 'Organizer', trunc(sysdate));
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'COMPETITOR', 'Competitor', trunc(sysdate));

insert into app_settings(setting_key, setting_value, setting_type, description, updated_at)
values ('ROUTE_R_EXACT_THRESHOLD', '10', 'NUMBER', 'Maximum included checkpoint count for exact R route calculation.', systimestamp);

insert into app_settings(setting_key, setting_value, setting_type, description, updated_at)
values ('ROUTE_JOB_BATCH_SIZE', '10', 'NUMBER', 'Maximum number of pending route calculations processed per scheduler run.', systimestamp);

insert into app_settings(setting_key, setting_value, setting_type, description, updated_at)
values ('ROUTE_HEURISTIC_SEED_COUNT', '6', 'NUMBER', 'Maximum number of seed starts for heuristic R route calculation.', systimestamp);

insert into app_settings(setting_key, setting_value, setting_type, description, updated_at)
values ('ROUTE_PROCESSING_TIMEOUT_MINUTES', '180', 'NUMBER', 'Timeout after which stuck PROCESSING route calculations are marked FAILED.', systimestamp);

begin
  dbms_scheduler.create_job(
    job_name        => 'FUNO_ROUTE_CALC_HOURLY',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'declare l_processed_count number; begin l_processed_count := FUNO_APP.pkg_competition_routes.process_pending_routes; end;',
    start_date      => systimestamp,
    repeat_interval => 'FREQ=HOURLY;INTERVAL=1',
    enabled         => true,
    comments        => 'Processes pending competition route calculations once per hour.'
  );
exception
  when others then
    if sqlcode = -27477 then
      dbms_scheduler.set_attribute(
        name      => 'FUNO_ROUTE_CALC_HOURLY',
        attribute => 'repeat_interval',
        value     => 'FREQ=HOURLY;INTERVAL=1'
      );
      dbms_scheduler.enable('FUNO_ROUTE_CALC_HOURLY');
    else
      raise;
    end if;
end;
/

commit;
