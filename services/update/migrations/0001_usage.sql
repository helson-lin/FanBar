CREATE TABLE releases (version TEXT PRIMARY KEY);
CREATE TABLE checks_daily (day TEXT NOT NULL, version TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (day, version));
CREATE TABLE cohort_weekly (week TEXT NOT NULL, value TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (week, value));
CREATE TABLE model_weekly (week TEXT NOT NULL, value TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (week, value));
CREATE TABLE os_weekly (week TEXT NOT NULL, value TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (week, value));
CREATE TABLE arch_weekly (week TEXT NOT NULL, value TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (week, value));
CREATE TABLE country_weekly (week TEXT NOT NULL, value TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (week, value));
