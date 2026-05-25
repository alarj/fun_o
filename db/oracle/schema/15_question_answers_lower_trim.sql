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
    begin
      execute immediate 'alter table QUESTION_ANSWERS drop constraint CHK_QA_NORMALIZE_MODE';
    exception
      when others then
        raise_application_error(-20003, 'Failed to drop constraint CHK_QA_NORMALIZE_MODE: ' || sqlerrm);
    end;
  end if;
end;
/

alter table QUESTION_ANSWERS add constraint CHK_QA_NORMALIZE_MODE
check (normalize_mode in ('EXACT', 'TRIM_UPPER', 'LOWER_TRIM', 'NUMERIC'));
