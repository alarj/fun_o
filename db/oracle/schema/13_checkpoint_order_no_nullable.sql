-- 13_checkpoint_order_no_nullable.sql
-- Run as FUNO_APP

alter table checkpoints modify (order_no null);

commit;
