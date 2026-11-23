"""Download one state's Medicare Part D Prescribers (by Provider and Drug) data from the CMS API.

Usage:
    python scripts/download_partd.py --state NJ --years 2023 2024

Writes data/raw/partd_<STATE>_<YEAR>.csv. The CMS API returns at most 5,000 rows per
request, so the script pages through the results with a few parallel workers.
"""

import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

# CMS dataset IDs (from https://data.cms.gov/data.json), one per data year.
DATASET_IDS = {
    2023: "e54db557-cd82-4e91-a0fe-61aad5865d69",
    2024: "9552739e-3d05-4c1b-8eff-ecabf391e2e5",
}
BASE = "https://data.cms.gov/data-api/v1/dataset/{id}/data"
PAGE_SIZE = 5000

COLUMNS = [
    "Prscrbr_NPI", "Prscrbr_Last_Org_Name", "Prscrbr_First_Name", "Prscrbr_City",
    "Prscrbr_State_Abrvtn", "Prscrbr_State_FIPS", "Prscrbr_Type", "Prscrbr_Type_Src",
    "Brnd_Name", "Gnrc_Name", "Tot_Clms", "Tot_30day_Fills", "Tot_Day_Suply",
    "Tot_Drug_Cst", "Tot_Benes", "GE65_Sprsn_Flag", "GE65_Tot_Clms",
    "GE65_Tot_30day_Fills", "GE65_Tot_Drug_Cst", "GE65_Tot_Day_Suply",
    "GE65_Bene_Sprsn_Flag", "GE65_Tot_Benes",
]


def fetch_page(session: requests.Session, dataset_id: str, state: str, offset: int) -> list[dict]:
    params = {
        "filter[Prscrbr_State_Abrvtn]": state,
        "size": PAGE_SIZE,
        "offset": offset,
    }
    for attempt in range(5):
        try:
            resp = session.get(BASE.format(id=dataset_id), params=params, timeout=60)
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException:
            if attempt == 4:
                raise
    return []


def row_count(session: requests.Session, dataset_id: str, state: str) -> int:
    url = BASE.format(id=dataset_id) + "/stats"
    resp = session.get(url, params={"filter[Prscrbr_State_Abrvtn]": state}, timeout=60)
    resp.raise_for_status()
    return int(resp.json()["found_rows"])


def download(state: str, year: int, out_dir: Path) -> Path:
    dataset_id = DATASET_IDS[year]
    session = requests.Session()
    total = row_count(session, dataset_id, state)
    offsets = range(0, total, PAGE_SIZE)
    print(f"{state} {year}: {total:,} rows in {len(offsets)} pages")

    with ThreadPoolExecutor(max_workers=8) as pool:
        pages = list(pool.map(lambda o: fetch_page(session, dataset_id, state, o), offsets))

    out_path = out_dir / f"partd_{state}_{year}.csv"
    written = 0
    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        for page in pages:
            writer.writerows(page)
            written += len(page)

    if written != total:
        raise RuntimeError(f"Expected {total} rows, wrote {written}")
    print(f"  wrote {out_path} ({written:,} rows)")
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", default="NJ")
    parser.add_argument("--years", type=int, nargs="+", default=[2023, 2024])
    parser.add_argument("--out-dir", type=Path, default=Path("data/raw"))
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for year in args.years:
        download(args.state.upper(), year, args.out_dir)


if __name__ == "__main__":
    main()
