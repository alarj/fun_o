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
create sequence seq_checkpoints start with 1 increment by 1;
create sequence seq_questions start with 1 increment by 1;
create sequence seq_submissions start with 1 increment by 1;
create sequence seq_materials start with 1 increment by 1;
create sequence seq_audit_log start with 1 increment by 1;

create table users (
  user_id number primary key,
  email varchar2(320) not null,
  full_name varchar2(200),
  google_sub varchar2(255) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint chk_users_dates check (end_date is null or end_date >= start_date)
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
  status varchar2(30) not null,
  starts_at timestamp,
  ends_at timestamp,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_comp_created_by foreign key (created_by) references users(user_id),
  constraint fk_comp_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_comp_dates check (end_date is null or end_date >= start_date)
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

create table competition_participants (
  competition_participant_id number primary key,
  competition_id number not null,
  user_id number not null,
  access_code_id number,
  status varchar2(30) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  joined_at timestamp default systimestamp not null,
  constraint fk_cp_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_cp_user foreign key (user_id) references users(user_id),
  constraint fk_cp_code foreign key (access_code_id) references competition_access_codes(access_code_id),
  constraint chk_cp_dates check (end_date is null or end_date >= start_date)
);

create table checkpoints (
  checkpoint_id number primary key,
  competition_id number not null,
  title varchar2(200) not null,
  order_no number not null,
  location_hint varchar2(500),
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint fk_chk_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_chk_created_by foreign key (created_by) references users(user_id),
  constraint fk_chk_updated_by foreign key (updated_by) references users(user_id),
  constraint chk_checkpoints_dates check (end_date is null or end_date >= start_date)
);

create table questions (
  question_id number primary key,
  checkpoint_id number not null,
  question_text varchar2(4000) not null,
  question_type varchar2(30) not null,
  points number default 0 not null,
  order_no number not null,
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
  constraint chk_questions_dates check (end_date is null or end_date >= start_date)
);

create table submissions (
  submission_id number primary key,
  competition_id number not null,
  checkpoint_id number not null,
  question_id number not null,
  user_id number not null,
  answer_text clob,
  awarded_points number,
  is_correct varchar2(1),
  submitted_at timestamp default systimestamp not null,
  evaluated_by number,
  evaluated_at timestamp,
  start_date date default trunc(sysdate) not null,
  end_date date,
  constraint fk_s_comp foreign key (competition_id) references competitions(competition_id),
  constraint fk_s_chk foreign key (checkpoint_id) references checkpoints(checkpoint_id),
  constraint fk_s_q foreign key (question_id) references questions(question_id),
  constraint fk_s_user foreign key (user_id) references users(user_id),
  constraint fk_s_eval_by foreign key (evaluated_by) references users(user_id),
  constraint chk_submissions_dates check (end_date is null or end_date >= start_date)
);

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

create unique index ux_active_comp_participant on competition_participants (
  case when end_date is null then competition_id end,
  case when end_date is null then user_id end
);

create unique index ux_active_comp_organizer on competition_organizers (
  case when end_date is null then competition_id end,
  case when end_date is null then user_id end
);

create unique index ux_active_cp_order on checkpoints (
  case when end_date is null then competition_id end,
  case when end_date is null then order_no end
);

create unique index ux_active_q_order on questions (
  case when end_date is null then checkpoint_id end,
  case when end_date is null then order_no end
);

-- Seed roles
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'SYSTEM_OWNER', 'System Owner', trunc(sysdate));
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'ORGANIZER', 'Organizer', trunc(sysdate));
insert into roles(role_id, role_code, role_name, start_date)
values (seq_roles.nextval, 'COMPETITOR', 'Competitor', trunc(sysdate));

commit;
