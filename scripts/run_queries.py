"""Build the SQL objects and run every named business query, saving each result to results/.

Usage:
    python scripts/run_queries.py

Runs, in order:
    sql/03_therapeutic_groups.sql   (lookup table, functions, molecule_group table)
    sql/04_prescriber_flags.sql     (view; its named queries are run too)
and every `-- name: <query>` block in sql/02, 03b and 04, writing results/<query>.csv
and printing each result.
"""

import re
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from db import connect, engine

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "sql"
RESULTS = ROOT / "results"

SETUP_FILES = ["03_therapeutic_groups.sql"]
QUERY_FILES = ["02_business_queries.sql", "03b_group_queries.sql", "04_prescriber_flags.sql"]


def split_named(sql_text: str) -> tuple[str, dict[str, str]]:
    """Return (preamble DDL before the first `-- name:`, {name: query})."""
    parts = re.split(r"^-- name:\s*(\w+)\s*$", sql_text, flags=re.MULTILINE)
    preamble, rest = parts[0], parts[1:]
    queries = {rest[i]: rest[i + 1].strip().rstrip(";") for i in range(0, len(rest), 2)}
    return preamble, queries


def main() -> None:
    RESULTS.mkdir(exist_ok=True)
    conn = connect()
    with conn, conn.cursor() as cur:
        for name in SETUP_FILES:
            cur.execute((SQL / name).read_text())
            print(f"ran {name}")
        for name in QUERY_FILES:
            preamble, _ = split_named((SQL / name).read_text())
            code = "\n".join(l for l in preamble.splitlines() if not l.strip().startswith("--"))
            if code.strip():
                cur.execute(preamble)   # e.g. the CREATE VIEW in 04
    conn.close()

    eng = engine()
    pd.set_option("display.width", 200, "display.max_columns", 20)
    for name in QUERY_FILES:
        _, queries = split_named((SQL / name).read_text())
        for qname, query in queries.items():
            df = pd.read_sql(text(query), eng)
            df.to_csv(RESULTS / f"{qname}.csv", index=False)
            print(f"\n=== {qname} ({len(df)} rows) ===")
            print(df.head(20).to_string(index=False))


if __name__ == "__main__":
    main()
