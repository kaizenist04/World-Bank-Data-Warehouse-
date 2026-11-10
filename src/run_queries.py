"""Run every query in sql/queries.sql and print the results."""
import sqlite3
from pathlib import Path

import pandas as pd

BASE_DIR = Path(__file__).resolve().parent.parent
sql_text = (BASE_DIR / "sql" / "queries.sql").read_text()

with sqlite3.connect(BASE_DIR / "data" / "warehouse.db") as conn:
    for i, query in enumerate(q.strip() for q in sql_text.split(";") if q.strip()):
        print(f"\n--- Query {i + 1} ---")
        print(pd.read_sql_query(query, conn).head(12).to_string(index=False))
