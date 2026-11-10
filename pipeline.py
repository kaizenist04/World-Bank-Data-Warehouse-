"""World Bank data warehouse pipeline.

Two API endpoints (country metadata + indicators) -> staging tables
-> quality checks -> star schema in SQLite.
"""
import sqlite3
import time
from datetime import datetime
from pathlib import Path

import pandas as pd
import requests

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "warehouse.db"
SCHEMA_PATH = BASE_DIR / "sql" / "schema.sql"

API = "https://api.worldbank.org/v2"
COUNTRIES = ["IN", "CN", "US", "BR", "ID", "NG", "JP", "DE", "GB", "ZA"]
START_YEAR, END_YEAR = 2010, 2023

INDICATORS = {
    "NY.GDP.PCAP.CD": "GDP per capita (current US$)",
    "SP.POP.TOTL": "Population, total",
    "SP.DYN.LE00.IN": "Life expectancy at birth (years)",
    "IT.NET.USER.ZS": "Individuals using the Internet (% of population)",
}
UNITS = {
    "NY.GDP.PCAP.CD": "US$",
    "SP.POP.TOTL": "people",
    "SP.DYN.LE00.IN": "years",
    "IT.NET.USER.ZS": "%",
}


# ---------- EXTRACT ----------
def get_json(url, params):
    """GET with retries, because public APIs can be slow."""
    for attempt in range(1, 4):
        try:
            resp = requests.get(url, params=params, timeout=90)
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            print(f"  Attempt {attempt}/3 failed: {type(e).__name__}")
            if attempt == 3:
                raise
            time.sleep(5 * attempt)


def get_all_pages(url, params):
    """The API splits big results into pages, so collect every page."""
    rows, page = [], 1
    while True:
        data = get_json(url, {**params, "page": page, "format": "json", "per_page": 500})
        meta, records = data[0], data[1] or []
        rows.extend(records)
        if page >= meta.get("pages", 1):
            return rows
        page += 1


def extract_countries():
    url = f"{API}/country/{';'.join(COUNTRIES)}"
    raw = get_all_pages(url, {})
    return pd.DataFrame([{
        "iso3": r["id"],
        "iso2": r["iso2Code"],
        "name": r["name"],
        "region": r["region"]["value"],
        "income_level": r["incomeLevel"]["value"],
    } for r in raw])


def extract_indicators():
    rows = []
    for code, name in INDICATORS.items():
        print(f"Extracting {name}...")
        url = f"{API}/country/{';'.join(COUNTRIES)}/indicator/{code}"
        raw = get_all_pages(url, {"date": f"{START_YEAR}:{END_YEAR}"})
        for r in raw:
            rows.append({
                "country_iso3": r["countryiso3code"],
                "indicator_code": code,
                "indicator_name": name,
                "year": int(r["date"]),
                "value": r["value"],
            })
    return pd.DataFrame(rows)


# ---------- TRANSFORM + QUALITY ----------
def clean_indicators(df):
    before = len(df)
    df = df.dropna(subset=["value"]).drop_duplicates(
        subset=["country_iso3", "indicator_code", "year"])
    df["value"] = pd.to_numeric(df["value"], errors="coerce")
    df = df.dropna(subset=["value"])
    print(f"Cleaning: {before} raw rows -> {len(df)} usable rows "
          f"({before - len(df)} missing values removed)")
    return df


def quality_checks(df):
    problems = []
    if df.empty:
        problems.append("no indicator data")
    if df.duplicated(subset=["country_iso3", "indicator_code", "year"]).any():
        problems.append("duplicate country/indicator/year rows")
    if (df.loc[df.indicator_code == "SP.POP.TOTL", "value"] <= 0).any():
        problems.append("population must be positive")
    if (df.loc[df.indicator_code == "NY.GDP.PCAP.CD", "value"] <= 0).any():
        problems.append("GDP per capita must be positive")
    life = df.loc[df.indicator_code == "SP.DYN.LE00.IN", "value"]
    if ((life < 30) | (life > 100)).any():
        problems.append("life expectancy outside 30-100 years")
    net = df.loc[df.indicator_code == "IT.NET.USER.ZS", "value"]
    if ((net < 0) | (net > 100)).any():
        problems.append("internet users outside 0-100 percent")
    missing = set(INDICATORS) - set(df["indicator_code"].unique())
    if missing:
        problems.append(f"no data for indicators: {sorted(missing)}")
    if problems:
        raise ValueError("Data quality check failed: " + "; ".join(problems))
    print("Quality checks passed.")


# ---------- LOAD ----------
def load_staging(conn, countries, indicators):
    conn.execute("DELETE FROM stg_countries")
    conn.execute("DELETE FROM stg_indicators")
    countries.to_sql("stg_countries", conn, if_exists="append", index=False)
    indicators.to_sql("stg_indicators", conn, if_exists="append", index=False)
    print(f"Staged {len(countries)} countries and {len(indicators)} indicator rows.")


def load_warehouse(conn):
    """Move data from staging into the star schema (safe to re-run)."""
    conn.execute("""
        INSERT OR IGNORE INTO dim_country (iso3, name, region, income_level)
        SELECT iso3, name, region, income_level FROM stg_countries
    """)
    conn.executemany(
        "INSERT OR IGNORE INTO dim_indicator (indicator_code, indicator_name, unit) "
        "VALUES (?, ?, ?)",
        [(c, n, UNITS[c]) for c, n in INDICATORS.items()])
    conn.execute("""
        INSERT OR IGNORE INTO dim_year (year_key, decade)
        SELECT DISTINCT year, (year / 10) * 10 FROM stg_indicators
    """)
    conn.execute("""
        INSERT OR REPLACE INTO fact_indicator
            (country_key, indicator_key, year_key, value)
        SELECT c.country_key, i.indicator_key, s.year, s.value
        FROM stg_indicators s
        JOIN dim_country   c ON c.iso3 = s.country_iso3
        JOIN dim_indicator i ON i.indicator_code = s.indicator_code
    """)


def run():
    DATA_DIR.mkdir(exist_ok=True)
    countries = extract_countries()
    indicators = clean_indicators(extract_indicators())
    quality_checks(indicators)

    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.executescript(SCHEMA_PATH.read_text())
        load_staging(conn, countries, indicators)
        load_warehouse(conn)
        fact_rows = conn.execute("SELECT COUNT(*) FROM fact_indicator").fetchone()[0]
        conn.execute(
            "INSERT INTO etl_run_log (run_time, rows_staged, rows_in_fact, status) "
            "VALUES (?, ?, ?, ?)",
            (datetime.now().isoformat(timespec="seconds"), len(indicators), fact_rows, "success"))
    print(f"Warehouse loaded: {fact_rows} rows in fact_indicator.")


if __name__ == "__main__":
    run()
