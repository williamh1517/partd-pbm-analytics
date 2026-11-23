-- 02_business_queries.sql
-- Each query answers one business question a PBM formulary or clinical team would ask.
-- `-- name:` markers let scripts/run_queries.py run each query and save it to results/.
-- All costs are gross Part D drug costs (plan + patient + other payers) BEFORE
-- manufacturer rebates, so brand-drug costs are overstated relative to net cost.

-- Molecules excluded from the generic-substitution estimate after a manual review of the
-- 30 largest results. The CMS file has no dosage-form or strength field, so one generic
-- name can cover products that are NOT interchangeable (e.g. extended- vs immediate-release,
-- injection vs tablet). Only the 30 largest molecules were reviewed; the rest are unreviewed.
DROP TABLE IF EXISTS substitution_exclusions CASCADE;
CREATE TABLE substitution_exclusions (gnrc_name TEXT PRIMARY KEY, reason TEXT NOT NULL);
INSERT INTO substitution_exclusions VALUES
('Cyclosporine',                  'Brand eye drops (Restasis, Cequa, Vevye) vs a generic name that also covers oral capsules; Cequa/Vevye have no generic'),
('Bimatoprost',                   'Lumigan 0.01% vs generic bimatoprost that may be a different strength; data has no strength'),
('Oxycodone Hcl',                 'OxyContin is extended-release; most generic oxycodone is immediate-release'),
('Aripiprazole',                  'Abilify Maintena / Asimtufii are long-acting injections; the generic is oral'),
('Insulin Glargine,hum.Rec.Anlog','Toujeo (U-300) and Basaglar are not interchangeable with generic U-100 glargine'),
('Carbidopa/Levodopa',            'Rytary is an extended-release capsule with no generic equivalent'),
('Azacitidine',                   'Onureg is an oral tablet; generic azacitidine is an injection'),
('Lidocaine',                     'Brand patches / topical systems vs other lidocaine forms'),
('Buprenorphine Hcl',             'Belbuca is a buccal film; generic buprenorphine is mostly sublingual tablets'),
('Tiotropium Bromide',            'Spiriva Respimat has no generic; only the HandiHaler form does');


-- name: q0_overview
-- Q0. How big is the market we are looking at?
SELECT data_year,
       COUNT(DISTINCT prscrbr_npi)                         AS prescribers,
       COUNT(DISTINCT gnrc_name)                           AS molecules,
       SUM(tot_clms)                                       AS claims,
       ROUND(SUM(tot_drug_cst) / 1e6, 1)                   AS cost_musd,
       ROUND(SUM(tot_drug_cst) / SUM(tot_clms), 2)         AS cost_per_claim
FROM prescriber_drug
GROUP BY data_year
ORDER BY data_year;


-- name: q1_top_drugs_by_spend
-- Q1. Which drugs drive spend? Top 20 products in the latest year, with share and
--     cumulative share of total cost (a Pareto view: how few drugs make up most spend).
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug),
drug AS (
    SELECT brnd_name, gnrc_name, BOOL_OR(is_brand) AS is_brand,
           SUM(tot_clms) AS claims, SUM(tot_drug_cst) AS cost
    FROM prescriber_drug
    WHERE data_year = (SELECT yr FROM latest)
    GROUP BY brnd_name, gnrc_name
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY cost DESC)                         AS spend_rank,
           cost / SUM(cost) OVER ()                                 AS share,
           SUM(cost) OVER (ORDER BY cost DESC ROWS UNBOUNDED PRECEDING)
               / SUM(cost) OVER ()                                  AS cum_share
    FROM drug
)
SELECT spend_rank, brnd_name, gnrc_name, is_brand, claims,
       ROUND(cost / 1e6, 1)         AS cost_musd,
       ROUND(cost / claims, 0)      AS cost_per_claim,
       ROUND(100 * share, 1)        AS pct_of_spend,
       ROUND(100 * cum_share, 1)    AS cum_pct_of_spend
FROM ranked
ORDER BY spend_rank
LIMIT 20;   -- LIMIT rather than WHERE spend_rank <= 20: some Postgres 16 builds mis-apply
            -- a filter on RANK() when the query has a second window (seen while testing)


-- name: q1b_spend_concentration
-- Q1b. How concentrated is spend? Share of total cost from the top 10 / 50 / 100 products.
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug),
drug AS (
    SELECT brnd_name, gnrc_name, SUM(tot_drug_cst) AS cost
    FROM prescriber_drug WHERE data_year = (SELECT yr FROM latest)
    GROUP BY 1, 2
),
ranked AS (
    SELECT cost, ROW_NUMBER() OVER (ORDER BY cost DESC) AS rn, COUNT(*) OVER () AS n_products
    FROM drug
)
SELECT MAX(n_products) AS products,
       ROUND(100 * SUM(cost) FILTER (WHERE rn <= 10)  / SUM(cost), 1) AS pct_top10,
       ROUND(100 * SUM(cost) FILTER (WHERE rn <= 50)  / SUM(cost), 1) AS pct_top50,
       ROUND(100 * SUM(cost) FILTER (WHERE rn <= 100) / SUM(cost), 1) AS pct_top100
FROM ranked;


-- name: q2_unit_cost
-- Q2. Where is the cost per prescription highest? For drugs with at least 1,000 claims,
--     cost per claim and per 30-day fill (30-day fills remove the effect of 90-day supplies).
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug)
SELECT brnd_name, gnrc_name,
       SUM(tot_clms)                                            AS claims,
       ROUND(SUM(tot_drug_cst) / 1e6, 2)                        AS cost_musd,
       ROUND(SUM(tot_drug_cst) / SUM(tot_clms), 0)              AS cost_per_claim,
       ROUND(SUM(tot_drug_cst) / NULLIF(SUM(tot_30day_fills), 0), 0) AS cost_per_30day_fill
FROM prescriber_drug
WHERE data_year = (SELECT yr FROM latest)
GROUP BY brnd_name, gnrc_name
HAVING SUM(tot_clms) >= 1000
ORDER BY cost_per_30day_fill DESC
LIMIT 20;


-- name: q3_brand_vs_generic
-- Q3. How much of the volume and the cost is brand vs generic, by year?
--     The classic PBM picture: generics are most of the claims, brands most of the cost.
SELECT data_year,
       CASE WHEN is_brand THEN 'Brand' ELSE 'Generic' END            AS product_type,
       SUM(tot_clms)                                                 AS claims,
       ROUND(100.0 * SUM(tot_clms) / SUM(SUM(tot_clms)) OVER (PARTITION BY data_year), 1)
                                                                     AS pct_of_claims,
       ROUND(SUM(tot_drug_cst) / 1e6, 1)                             AS cost_musd,
       ROUND(100.0 * SUM(tot_drug_cst) / SUM(SUM(tot_drug_cst)) OVER (PARTITION BY data_year), 1)
                                                                     AS pct_of_cost,
       ROUND(SUM(tot_drug_cst) / SUM(tot_clms), 0)                   AS cost_per_claim
FROM prescriber_drug
GROUP BY data_year, is_brand
ORDER BY data_year, product_type;


-- name: q4_yoy_growth
-- Q4. What is growing fastest, and is it more patients (utilization) or higher prices?
--     LAG compares each drug's latest year with the prior year. Growth in cost is split
--     into claims growth (volume) and cost-per-day-supply growth (unit cost).
WITH by_year AS (
    SELECT brnd_name, gnrc_name, data_year,
           SUM(tot_clms)      AS claims,
           SUM(tot_day_suply) AS day_supply,
           SUM(tot_drug_cst)  AS cost
    FROM prescriber_drug
    GROUP BY brnd_name, gnrc_name, data_year
),
with_prior AS (
    SELECT *,
           LAG(data_year) OVER w AS prior_year,
           LAG(claims)    OVER w AS prior_claims,
           LAG(day_supply) OVER w AS prior_day_supply,
           LAG(cost)      OVER w AS prior_cost
    FROM by_year
    WINDOW w AS (PARTITION BY brnd_name, gnrc_name ORDER BY data_year)
)
SELECT brnd_name, gnrc_name,
       ROUND(prior_cost / 1e6, 1)                                        AS prior_cost_musd,
       ROUND(cost / 1e6, 1)                                              AS cost_musd,
       ROUND((cost - prior_cost) / 1e6, 1)                               AS change_musd,
       ROUND(100 * (cost / prior_cost - 1), 1)                           AS pct_cost_growth,
       ROUND(100 * (claims::NUMERIC / prior_claims - 1), 1)              AS pct_claims_growth,
       ROUND(100 * ((cost / day_supply) / (prior_cost / prior_day_supply) - 1), 1)
                                                                         AS pct_unit_cost_growth
FROM with_prior
WHERE prior_year = data_year - 1
  AND prior_cost >= 1e6                 -- ignore tiny drugs where % growth is noise
ORDER BY change_musd DESC
LIMIT 20;


-- name: q4b_market_growth
-- Q4b. Total market growth, split the same way.
WITH t AS (
    SELECT data_year, SUM(tot_clms) AS claims, SUM(tot_day_suply) AS day_supply,
           SUM(tot_drug_cst) AS cost
    FROM prescriber_drug GROUP BY data_year
)
SELECT data_year,
       ROUND(cost / 1e6, 1)                                                    AS cost_musd,
       ROUND(100 * (cost / LAG(cost) OVER (ORDER BY data_year) - 1), 1)        AS pct_cost_growth,
       ROUND(100 * (claims::NUMERIC / LAG(claims) OVER (ORDER BY data_year) - 1), 1)
                                                                               AS pct_claims_growth,
       ROUND(100 * ((cost / day_supply)
             / LAG(cost / day_supply) OVER (ORDER BY data_year) - 1), 1)       AS pct_unit_cost_growth
FROM t ORDER BY data_year;


-- name: q5_generic_substitution
-- Q5. What would switching brand fills to an available generic save?
--     For each molecule that is sold BOTH as a brand and as a generic in the latest year,
--     savings = brand days of supply x (brand cost per day - generic cost per day).
--     Per-day cost is used because brand and generic fills can differ in length.
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug),
mol AS (
    SELECT gnrc_name,
           SUM(tot_clms)      FILTER (WHERE is_brand)     AS brand_claims,
           SUM(tot_day_suply) FILTER (WHERE is_brand)     AS brand_days,
           SUM(tot_drug_cst)  FILTER (WHERE is_brand)     AS brand_cost,
           SUM(tot_clms)      FILTER (WHERE NOT is_brand) AS generic_claims,
           SUM(tot_day_suply) FILTER (WHERE NOT is_brand) AS generic_days,
           SUM(tot_drug_cst)  FILTER (WHERE NOT is_brand) AS generic_cost,
           STRING_AGG(DISTINCT brnd_name, ', ') FILTER (WHERE is_brand) AS brand_names
    FROM prescriber_drug
    WHERE data_year = (SELECT yr FROM latest)
    GROUP BY gnrc_name
),
calc AS (
    SELECT *,
           brand_cost / brand_days     AS brand_cost_per_day,
           generic_cost / generic_days AS generic_cost_per_day,
           brand_days * (brand_cost / brand_days - generic_cost / generic_days) AS savings
    FROM mol
    WHERE brand_days > 0 AND generic_days > 0
)
SELECT gnrc_name, LEFT(brand_names, 60) AS brand_names, brand_claims, generic_claims,
       ROUND(100.0 * brand_claims / (brand_claims + generic_claims), 1) AS pct_filled_as_brand,
       ROUND(brand_cost_per_day, 2)    AS brand_cost_per_day,
       ROUND(generic_cost_per_day, 2)  AS generic_cost_per_day,
       ROUND(savings / 1e6, 2)         AS est_savings_musd
FROM calc
WHERE savings > 0
  AND gnrc_name NOT IN (SELECT gnrc_name FROM substitution_exclusions)
ORDER BY savings DESC
LIMIT 20;


-- name: q5b_generic_substitution_total
-- Q5b. Total estimated savings across all multi-source molecules (gross, before rebates):
--      raw (every molecule) and reviewed (after the formulation exclusions above).
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug),
mol AS (
    SELECT gnrc_name,
           SUM(tot_day_suply) FILTER (WHERE is_brand)     AS brand_days,
           SUM(tot_drug_cst)  FILTER (WHERE is_brand)     AS brand_cost,
           SUM(tot_day_suply) FILTER (WHERE NOT is_brand) AS generic_days,
           SUM(tot_drug_cst)  FILTER (WHERE NOT is_brand) AS generic_cost
    FROM prescriber_drug WHERE data_year = (SELECT yr FROM latest)
    GROUP BY gnrc_name
),
calc AS (
    SELECT gnrc_name, brand_cost,
           GREATEST(brand_days * (brand_cost / brand_days - generic_cost / generic_days), 0) AS savings,
           gnrc_name IN (SELECT gnrc_name FROM substitution_exclusions)                      AS excluded
    FROM mol WHERE brand_days > 0 AND generic_days > 0
),
total AS (SELECT SUM(tot_drug_cst) AS cost FROM prescriber_drug
          WHERE data_year = (SELECT yr FROM latest))
SELECT COUNT(*) FILTER (WHERE savings > 0)                                   AS molecules_with_savings,
       ROUND(SUM(brand_cost) / 1e6, 1)                                       AS multisource_brand_cost_musd,
       ROUND(SUM(savings) / 1e6, 1)                                          AS raw_savings_musd,
       ROUND(SUM(savings) FILTER (WHERE NOT excluded) / 1e6, 1)              AS est_savings_musd,
       ROUND(100 * SUM(savings) FILTER (WHERE NOT excluded) / MAX(total.cost), 2) AS pct_of_total_spend
FROM calc, total;
