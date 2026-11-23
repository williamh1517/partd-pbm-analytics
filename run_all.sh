#!/usr/bin/env bash
# Reproduce the whole project: database, data, SQL, notebook.
set -euo pipefail

docker compose up -d
sleep 5
python scripts/download_partd.py --state NJ --years 2023 2024
python scripts/load_partd.py
python scripts/run_queries.py
jupyter nbconvert --to notebook --execute --inplace notebooks/partd_analysis.ipynb
echo "Done. Results in results/, charts in results/figures/."
