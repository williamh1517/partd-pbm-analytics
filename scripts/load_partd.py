"""Load the downloaded CSVs into Postgres.

Usage:
    python scripts/load_partd.py            # loads every data/raw/partd_*_*.csv

Steps: run sql/01_schema.sql, COPY each file into a text staging table,
cast into the typed prescriber_drug table with its data year, then print
row counts and basic checks.
"""

import re
from pathlib import Path

from db import connect

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"

STAGING_DDL = """
DROP TABLE IF EXISTS stg_prescriber_drug;
CREATE TEMP TABLE stg_prescriber_drug (
    prscrbr_npi TEXT, prscrbr_last_org_name TEXT, prscrbr_first_name TEXT,
    prscrbr_city TEXT, prscrbr_state_abrvtn TEXT, prscrbr_state_fips TEXT,
    prscrbr_type TEXT, prscrbr_type_src TEXT, brnd_name TEXT, gnrc_name TEXT,
    tot_clms TEXT, tot_30day_fills TEXT, tot_day_suply TEXT, tot_drug_cst TEXT,
    tot_benes TEXT, ge65_sprsn_flag TEXT, ge65_tot_clms TEXT, ge65_tot_30day_fills TEXT,
    ge65_tot_drug_cst TEXT, ge65_tot_day_suply TEXT, ge65_bene_sprsn_flag TEXT,
    ge65_tot_benes TEXT
);
"""

INSERT_SQL = """
INSERT INTO prescriber_drug (
    data_year, prscrbr_npi, prscrbr_last_org_name, prscrbr_first_name, prscrbr_city,
    prscrbr_state, prscrbr_type, prscrbr_type_src, brnd_name, gnrc_name,
    tot_clms, tot_30day_fills, tot_day_suply, tot_drug_cst, tot_benes
)
SELECT %(year)s,
       prscrbr_npi::BIGINT,
       prscrbr_last_org_name, prscrbr_first_name, prscrbr_city,
       prscrbr_state_abrvtn, prscrbr_type, prscrbr_type_src,
       TRIM(brnd_name), TRIM(gnrc_name),
       tot_clms::INTEGER,
       NULLIF(tot_30day_fills, '')::NUMERIC,
       NULLIF(tot_day_suply, '')::NUMERIC::INTEGER,
       tot_drug_cst::NUMERIC,
       NULLIF(tot_benes, '')::INTEGER
FROM stg_prescriber_drug;
"""


def main() -> None:
    files = sorted(RAW.glob("partd_*_*.csv"))
    if not files:
        raise SystemExit("No files in data/raw. Run scripts/download_partd.py first.")

    conn = connect()
    with conn, conn.cursor() as cur:
        cur.execute((ROOT / "sql" / "01_schema.sql").read_text())
        for path in files:
            year = int(re.search(r"_(\d{4})\.csv$", path.name).group(1))
            cur.execute(STAGING_DDL)
            with path.open() as f:
                cur.copy_expert("COPY stg_prescriber_drug FROM STDIN WITH (FORMAT csv, HEADER true)", f)
            cur.execute(INSERT_SQL, {"year": year})
            print(f"{path.name}: loaded {cur.rowcount:,} rows as data_year {year}")

        cur.execute("""
            SELECT data_year, COUNT(*) AS rows, COUNT(DISTINCT prscrbr_npi) AS prescribers,
                   COUNT(DISTINCT gnrc_name) AS generics, SUM(tot_clms) AS claims,
                   ROUND(SUM(tot_drug_cst) / 1e6, 1) AS cost_musd,
                   ROUND(100.0 * AVG((tot_benes IS NULL)::INT), 1) AS pct_benes_suppressed
            FROM prescriber_drug GROUP BY data_year ORDER BY data_year
        """)
        print("\ndata_year | rows | prescribers | generics | claims | cost $M | % bene counts suppressed")
        for row in cur.fetchall():
            print(" | ".join([str(row[0])] + [f"{v:,}" if isinstance(v, int) else str(v) for v in row[1:]]))

        # Sanity checks: no duplicate keys, no negative values.
        cur.execute("""
            SELECT COUNT(*) FROM (
                SELECT data_year, prscrbr_npi, brnd_name, gnrc_name
                FROM prescriber_drug GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1) d
        """)
        print(f"\nduplicate prescriber-drug-year rows: {cur.fetchone()[0]}")
        cur.execute("SELECT COUNT(*) FROM prescriber_drug WHERE tot_drug_cst < 0 OR tot_clms < 11")
        print(f"rows with negative cost or <11 claims: {cur.fetchone()[0]}")
    conn.close()


if __name__ == "__main__":
    main()
