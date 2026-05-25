-- 16_fix_checkpoint_order_unique_index.sql
-- Make checkpoint order uniqueness apply only when ORDER_NO is present.

declare
  l_count number;
begin
  select count(*)
    into l_count
    from user_indexes
   where index_name = 'UX_ACTIVE_CP_ORDER';

  if l_count > 0 then
    begin
      execute immediate 'drop index UX_ACTIVE_CP_ORDER';
    exception
      when others then
        raise_application_error(-20004, 'Failed to drop index UX_ACTIVE_CP_ORDER: ' || sqlerrm);
    end;
  end if;
end;
/

create unique index UX_ACTIVE_CP_ORDER on CHECKPOINTS (
  case when end_date is null and order_no is not null then competition_id end,
  case when end_date is null and order_no is not null then order_no end
);
