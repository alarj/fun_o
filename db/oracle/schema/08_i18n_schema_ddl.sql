-- 08_i18n_schema_ddl.sql
-- Run as FUNO_APP after 04_app_schema_ddl.sql

create table translations (
  translation_id number primary key,
  translation_key varchar2(300) not null,
  lang_code varchar2(10) not null,
  text_value varchar2(4000) not null,
  start_date date default trunc(sysdate) not null,
  end_date date,
  created_by number,
  updated_by number,
  created_at timestamp default systimestamp not null,
  updated_at timestamp,
  constraint chk_translations_dates check (end_date is null or end_date >= start_date),
  constraint chk_translations_lang check (regexp_like(lang_code, '^[a-z]{2}(-[A-Z]{2})?$')),
  constraint fk_translations_created_by foreign key (created_by) references users(user_id),
  constraint fk_translations_updated_by foreign key (updated_by) references users(user_id)
);

create sequence seq_translations start with 1 increment by 1;

create unique index ux_translations_key_lang_active on translations (
  case when end_date is null then translation_key end,
  case when end_date is null then lower(lang_code) end
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

create sequence seq_question_texts start with 1 increment by 1;

create unique index ux_qt_question_lang_active on question_texts (
  case when end_date is null then question_id end,
  case when end_date is null then lower(lang_code) end
);

comment on table translations is 'UI translation dictionary. Not part of audit_log tracking by design.';
comment on table question_texts is 'Localized question text values by language.';

commit;