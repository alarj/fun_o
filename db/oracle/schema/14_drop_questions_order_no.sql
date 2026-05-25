-- 14_drop_questions_order_no.sql
-- Remove obsolete question ordering from data model.

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_indexes
   where index_name = 'UX_ACTIVE_Q_ORDER';
  if l_count > 0 then
    begin
      execute immediate 'drop index UX_ACTIVE_Q_ORDER';
    exception
      when others then
        raise_application_error(-20001, 'Failed to drop index UX_ACTIVE_Q_ORDER: ' || sqlerrm);
    end;
  end if;
end;
/

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_tab_columns
   where table_name = 'QUESTIONS'
     and column_name = 'ORDER_NO';
  if l_count > 0 then
    begin
      execute immediate 'alter table QUESTIONS drop column ORDER_NO';
    exception
      when others then
        raise_application_error(-20002, 'Failed to drop column QUESTIONS.ORDER_NO: ' || sqlerrm);
    end;
  end if;
end;
/
