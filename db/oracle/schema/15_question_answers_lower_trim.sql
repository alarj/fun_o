-- 15_question_answers_lower_trim.sql
-- Adds LOWER_TRIM normalize mode support for question_answers.

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_constraints
   where constraint_name = 'CHK_QA_NORMALIZE_MODE'
     and table_name = 'QUESTION_ANSWERS';

  if l_count > 0 then
    execute immediate 'alter table QUESTION_ANSWERS drop constraint CHK_QA_NORMALIZE_MODE';
  end if;
end;
/

alter table QUESTION_ANSWERS add constraint CHK_QA_NORMALIZE_MODE
check (normalize_mode in ('EXACT', 'TRIM_UPPER', 'LOWER_TRIM', 'NUMERIC'));

