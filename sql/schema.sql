-- STAGING LAYER: raw data exactly as it arrives from the API
CREATE TABLE IF NOT EXISTS stg_countries (
    iso3         TEXT,
    iso2         TEXT,
    name         TEXT,
    region       TEXT,
    income_level TEXT
);

CREATE TABLE IF NOT EXISTS stg_indicators (
    country_iso3   TEXT,
    indicator_code TEXT,
    indicator_name TEXT,
    year           INTEGER,
    value          REAL
);

-- WAREHOUSE LAYER: star schema (dimensions + one fact table)
CREATE TABLE IF NOT EXISTS dim_country (
    country_key  INTEGER PRIMARY KEY AUTOINCREMENT,
    iso3         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    region       TEXT,
    income_level TEXT
);

CREATE TABLE IF NOT EXISTS dim_indicator (
    indicator_key  INTEGER PRIMARY KEY AUTOINCREMENT,
    indicator_code TEXT NOT NULL UNIQUE,
    indicator_name TEXT NOT NULL,
    unit           TEXT
);

CREATE TABLE IF NOT EXISTS dim_year (
    year_key INTEGER PRIMARY KEY,
    decade   INTEGER
);

CREATE TABLE IF NOT EXISTS fact_indicator (
    country_key   INTEGER NOT NULL,
    indicator_key INTEGER NOT NULL,
    year_key      INTEGER NOT NULL,
    value         REAL    NOT NULL,
    PRIMARY KEY (country_key, indicator_key, year_key),
    FOREIGN KEY (country_key)   REFERENCES dim_country(country_key),
    FOREIGN KEY (indicator_key) REFERENCES dim_indicator(indicator_key),
    FOREIGN KEY (year_key)      REFERENCES dim_year(year_key)
);

CREATE INDEX IF NOT EXISTS idx_fact_country   ON fact_indicator(country_key);
CREATE INDEX IF NOT EXISTS idx_fact_indicator ON fact_indicator(indicator_key);

-- RUN LOG: one row per pipeline run
CREATE TABLE IF NOT EXISTS etl_run_log (
    run_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    run_time     TEXT,
    rows_staged  INTEGER,
    rows_in_fact INTEGER,
    status       TEXT
);
