-- 09_question_answer_model_migration.sql
-- Run as FUNO_APP on existing database (incremental migration).

alter table questions add (input_type varchar2(30));
alter table questions add (input_max_length number);
alter table questions add (input_pattern varchar2(300));
alter table questions add (placeholder_key varchar2(300));
alter table questions add (help_text_key varchar2(300));

alter table questions add constraint chk_question_type check (question_type in ('TEXT', 'SINGLE_CHOICE'));
alter table questions add constraint chk_input_type check (input_type is null or input_type in ('TEXT', 'NUMERIC'));
alter table questions add constraint chk_input_max_length check (input_max_length is null or input_max_length > 0);

create sequence seq_question_texts start with 1 increment by 1;
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

create unique index ux_active_qt_lang on question_texts (
  case when end_date is null then question_id end,
  case when end_date is null then lower(lang_code) end
);

create sequence seq_question_options start with 1 increment by 1;
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

create unique index ux_active_qo_code on question_options (
  case when end_date is null then question_id end,
  case when end_date is null then option_code end
);

create unique index ux_active_qo_order on question_options (
  case when end_date is null then question_id end,
  case when end_date is null then order_no end
);

create sequence seq_question_option_texts start with 1 increment by 1;
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

create unique index ux_active_qot_lang on question_option_texts (
  case when end_date is null then option_id end,
  case when end_date is null then lower(lang_code) end
);

create sequence seq_question_answers start with 1 increment by 1;
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
  constraint chk_qa_normalize_mode check (normalize_mode in ('EXACT', 'TRIM_UPPER', 'NUMERIC'))
);

alter table submissions add (selected_option_id number);
alter table submissions add constraint fk_s_selected_option foreign key (selected_option_id) references question_options(option_id);

commit;