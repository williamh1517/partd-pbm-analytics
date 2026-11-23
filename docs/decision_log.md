# Decision log

Each entry: the decision, the options considered, and why.

### 1. Data: one state, two years
**Chose:** New Jersey, data years 2023 and 2024 (the latest CMS release).
**Why:** two years are the minimum for year-over-year analysis with `LAG`. One state keeps the data around 100 MB per year so it runs on a laptop, while still giving about 30,000 prescribers, enough for within-specialty comparisons. New Jersey is a large, diverse Medicare market.

### 2. Database: PostgreSQL in Docker
**Chose:** Postgres 17 via `docker-compose`, on port 5433.
**Why:** the project uses functions and views (and later stored procedures), which DuckDB and SQLite do not fully support. Docker makes setup one command, and port 5433 avoids clashing with another local Postgres.

### 3. Loading: text staging table, then cast
**Chose:** `COPY` into an all-text staging table, then `INSERT … SELECT` with explicit casts.
**Why:** CMS leaves suppressed values blank. Loading as text first means a bad value fails loudly in one known place (the cast), and blanks become `NULL` on purpose (`NULLIF(x, '')`) rather than by accident. The loader then checks row counts against the API, duplicate keys, and the CMS minimum of 11 claims.

### 4. Brand vs generic flag (revised after the first run)
**First version:** brand if the brand name differs from the generic name.
**Problem found:** generics such as `Metformin Hcl Er`, `Clopidogrel` and `Insulin Lispro Kwikpen` were flagged as brand, because their "brand name" is the molecule plus a form or salt. The brand share of claims came out at 24%, about double the true figure.
**Fix:** a product is generic when its brand name starts with the first word of the molecule name. That brought the brand share of claims to 12.8%, in line with national figures of roughly 10–15%.
**Remaining limitation:** branded generics with trade names (e.g. contraceptives like Aviane) still count as brand. They are cheap, so the cost results barely change.

### 5. Generic-substitution savings: per day of supply, with a reviewed exclusion list
**Chose:** savings = brand days of supply × (brand cost per day − generic cost per day), for molecules with both brand and generic rows in the same year.
**Why per day:** brand and generic fills can differ in length (30- vs 90-day). Per claim would favour whichever form is filled in longer supplies.
**Exclusions:** the CMS file has no dosage-form or strength field. Reviewing the 30 largest results showed 10 where the brand and the "generic" are not interchangeable: OxyContin (extended-release) vs immediate-release oxycodone, Abilify Maintena (injection) vs oral aripiprazole, Restasis eye drops vs a generic name that also covers oral cyclosporine, and so on. These are in `substitution_exclusions`, each with its reason. The raw estimate ($295M) and the reviewed one ($198M) are both reported.
**Not done:** rebates. A brand with a large rebate can cost a plan less, net, than its generic. The estimate is gross and an upper bound.

### 6. Therapeutic groups: hand-built pattern table + SQL function
**Options:** a standard classification (USP category or ATC via RxNorm), or a hand-built mapping.
**Chose:** a lookup table of 239 `LIKE` patterns with a priority column, used by `fn_drug_group()`.
**Why:** it keeps the project self-contained and every mapping readable. Priority handles combination products (sacubitril/valsartan is heart failure, not a blood-pressure ARB). The function runs once per molecule (about 1,500 across both years) into `molecule_group`, not once per row (1.4M). Coverage is reported (79.5% of spend) so the reader knows what is unmapped. A production version should use RxNorm.

### 7. Prescriber flags: percentiles within specialty, with minimums
**Chose:** flag a prescriber in the top 5% of their specialty for (a) cost per claim or (b) brand rate on multi-source molecules, with at least 200 claims, at least 50 multi-source claims for the brand rate, and at least 30 peers in the specialty.
**Why within specialty:** an oncologist's cost per claim is many times a family doctor's for legitimate reasons. Comparing within specialty removes the largest source of difference.
**Why brand rate on multi-source molecules only:** brands with no generic cannot be switched, so including them would flag prescribers for things outreach cannot change.
**Why percentiles, not z-scores:** cost per claim is heavily right-skewed (see the histogram in the notebook). A z-score threshold would depend on a few extreme values; a percentile does not.
**Why the minimums:** a rate based on 15 claims is noise.
**Known weakness:** nurse practitioners and physician assistants work across specialties, so their peer group is mixed, and they are the most-flagged groups. A next step would assign them a specialty from the drugs they prescribe.

### 8. No prescriber identifiers in published results
**Chose:** the outreach-list output shows rank and specialty only, not NPI or name.
**Why:** prescriber names and NPIs are public in the CMS file, but a statistical flag is not a finding about a person, and a public repo is not the place to list individuals as outliers. The view in the database keeps the identifiers for internal use.

### 9. A Postgres quirk found while testing
`WHERE spend_rank <= 20` on a `RANK()` column returned every row on Postgres 16.15 when the same query had a second window function (a running total). `ORDER BY spend_rank LIMIT 20` gives the intended result on any version, so Q1 uses that instead.
