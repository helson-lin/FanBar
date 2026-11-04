-- The daily task runs from the first update check of each UTC day (the account has no cron slot left).
CREATE TABLE task_runs (task TEXT PRIMARY KEY, day TEXT NOT NULL);
INSERT INTO task_runs (task, day) VALUES ('daily', '');
