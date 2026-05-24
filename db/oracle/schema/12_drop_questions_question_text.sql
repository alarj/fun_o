-- 12_drop_questions_question_text.sql
-- Run as FUNO_APP
-- Drops legacy column no longer used after question_texts migration.

alter table questions drop column question_text;

commit;
