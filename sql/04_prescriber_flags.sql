-- 04_prescriber_flags.sql
-- Rules-based prescriber flag: who prescribes far more costly, or far more brand-heavy,
-- than other prescribers in the SAME specialty?
--
-- Use case: a PBM clinical team choosing prescribers for outreach (e.g. a pharmacist call
-- about generic alternatives). It is NOT a fraud signal: a high-cost prescriber may simply
-- treat sicker patients. Comparing within specialty removes the biggest source of
-- legitimate difference (an oncologist vs a family doctor), but not all of it.
--
-- Metrics per prescriber (latest year, prescribers with >= 200 claims):
--   cost_per_claim   total cost / total claims
--   brand_rate_msb   of the claims for molecules where a generic exists in this state and
--                    year ("multi-source" molecules), the share filled as brand. This is the
--                    actionable brand share: brands with no generic are excluded, because
--                    there is nothing to switch to.
-- Peer groups: specialties with >= 30 eligible prescribers.
-- Flags (top 5% of the specialty, by percentile rank):
--   high_cost  = cost per claim at or above the 95th percentile
--   high_brand = brand rate on multi-source molecules at or above the 95th percentile
--                (needs >= 50 multi-source claims) and above 10% in absolute terms
-- excess_cost  = (cost per claim - specialty median) x claims, when positive.
--   This is an upper bound on what outreach could move, not a savings estimate.
-- Thresholds live in the `params` CTE so they are easy to change and to explain.

DROP VIEW IF EXISTS vw_prescriber_flags;

CREATE VIEW vw_prescriber_flags AS
WITH params AS (
    SELECT 200  AS min_claims,
           50   AS min_msb_claims,
           30   AS min_peers,
           0.95 AS pct_threshold,
           0.10 AS min_brand_rate
),
latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug),
multisource AS (
    SELECT gnrc_name
    FROM prescriber_drug
    WHERE data_year = (SELECT yr FROM latest)
      AND gnrc_name NOT IN (SELECT gnrc_name FROM substitution_exclusions)  -- see sql/02
    GROUP BY gnrc_name
    HAVING BOOL_OR(is_brand) AND BOOL_OR(NOT is_brand)
),
prescriber AS (
    SELECT p.prscrbr_npi,
           MAX(p.prscrbr_last_org_name)  AS last_org_name,
           MAX(p.prscrbr_first_name)     AS first_name,
           MAX(p.prscrbr_city)           AS city,
           MAX(p.prscrbr_type)           AS specialty,
           SUM(p.tot_clms)               AS claims,
           SUM(p.tot_drug_cst)           AS cost,
           COALESCE(SUM(p.tot_clms) FILTER (WHERE ms.gnrc_name IS NOT NULL), 0)                AS msb_claims,
           COALESCE(SUM(p.tot_clms) FILTER (WHERE ms.gnrc_name IS NOT NULL AND p.is_brand), 0) AS msb_brand_claims
    FROM prescriber_drug p
    LEFT JOIN multisource ms USING (gnrc_name)
    WHERE p.data_year = (SELECT yr FROM latest)
    GROUP BY p.prscrbr_npi
),
eligible AS (
    SELECT pr.*,
           pr.cost / pr.claims                                  AS cost_per_claim,
           CASE WHEN pr.msb_claims >= (SELECT min_msb_claims FROM params)
                THEN pr.msb_brand_claims::NUMERIC / pr.msb_claims END AS brand_rate_msb
    FROM prescriber pr
    WHERE pr.claims >= (SELECT min_claims FROM params)
),
peer_stats AS (                 -- one row per specialty
    SELECT specialty,
           COUNT(*)                                                       AS peers,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cost_per_claim)    AS median_cost_per_claim,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY brand_rate_msb)    AS median_brand_rate_msb
    FROM eligible
    GROUP BY specialty
    HAVING COUNT(*) >= (SELECT min_peers FROM params)
),
scored AS (
    SELECT e.*, s.peers, s.median_cost_per_claim, s.median_brand_rate_msb,
           PERCENT_RANK() OVER (PARTITION BY e.specialty ORDER BY e.cost_per_claim) AS pr_cost,
           -- rank brand rate only among prescribers that have one (NULLs sort into their own partition)
           CASE WHEN e.brand_rate_msb IS NOT NULL THEN
               PERCENT_RANK() OVER (PARTITION BY e.specialty, (e.brand_rate_msb IS NULL)
                                    ORDER BY e.brand_rate_msb)
           END                                                                    AS pr_brand
    FROM eligible e
    JOIN peer_stats s USING (specialty)
)
SELECT prscrbr_npi, last_org_name, first_name, city, specialty, peers,
       claims,
       ROUND(cost, 0)                                   AS cost,
       ROUND(cost_per_claim, 2)                         AS cost_per_claim,
       ROUND(median_cost_per_claim::NUMERIC, 2)         AS specialty_median_cost_per_claim,
       ROUND(pr_cost::NUMERIC, 3)                       AS pctile_cost,
       msb_claims,
       ROUND(brand_rate_msb, 3)                         AS brand_rate_msb,
       ROUND(median_brand_rate_msb::NUMERIC, 3)         AS specialty_median_brand_rate_msb,
       ROUND(pr_brand::NUMERIC, 3)                      AS pctile_brand,
       pr_cost >= (SELECT pct_threshold FROM params)    AS high_cost,
       COALESCE(pr_brand >= (SELECT pct_threshold FROM params)
                AND brand_rate_msb >= (SELECT min_brand_rate FROM params), FALSE) AS high_brand,
       ROUND(GREATEST(cost_per_claim - median_cost_per_claim::NUMERIC, 0) * claims, 0) AS excess_cost
FROM scored;


-- name: q8_flag_summary
-- Q8. How many prescribers are flagged, and how much excess cost sits with them?
SELECT CASE WHEN high_cost AND high_brand THEN 'Both flags'
            WHEN high_cost  THEN 'High cost per claim only'
            WHEN high_brand THEN 'High brand rate only'
            ELSE 'Not flagged' END                         AS flag,
       COUNT(*)                                            AS prescribers,
       SUM(claims)                                         AS claims,
       ROUND(SUM(cost) / 1e6, 1)                           AS cost_musd,
       ROUND(SUM(excess_cost) / 1e6, 1)                    AS excess_cost_musd
FROM vw_prescriber_flags
GROUP BY 1
ORDER BY 1;


-- name: q8b_flags_by_specialty
-- Q8b. Which specialties hold the most excess cost among flagged prescribers?
SELECT specialty,
       MAX(peers)                                          AS eligible_prescribers,
       COUNT(*) FILTER (WHERE high_cost OR high_brand)     AS flagged,
       ROUND(MAX(specialty_median_cost_per_claim), 0)      AS median_cost_per_claim,
       ROUND(SUM(excess_cost) FILTER (WHERE high_cost OR high_brand) / 1e6, 2) AS flagged_excess_cost_musd
FROM vw_prescriber_flags
GROUP BY specialty
ORDER BY flagged_excess_cost_musd DESC NULLS LAST
LIMIT 15;


-- name: q8c_brand_outreach_list
-- Q8c. What would an outreach list look like? Prescribers flagged for high brand use on
--      molecules that have a generic, ranked by brand claims above the specialty median
--      (the claims a pharmacist call could realistically move).
--      NPIs and names are public in the CMS file, but they are left out of the published
--      results on purpose: a statistical flag is a reason to look, not a finding about a person.
SELECT ROW_NUMBER() OVER (ORDER BY msb_claims * (brand_rate_msb - specialty_median_brand_rate_msb) DESC)
                                                       AS outreach_rank,
       specialty, claims, msb_claims,
       brand_rate_msb, specialty_median_brand_rate_msb,
       ROUND(msb_claims * (brand_rate_msb - specialty_median_brand_rate_msb)) AS brand_claims_above_median
FROM vw_prescriber_flags
WHERE high_brand
ORDER BY outreach_rank
LIMIT 15;
