-- 03b_group_queries.sql
-- Queries that use the therapeutic-group mapping from 03_therapeutic_groups.sql.


-- name: q6_mapping_coverage
-- Q6. How much of the spend does the hand-built mapping cover?
WITH latest AS (SELECT MAX(data_year) AS yr FROM prescriber_drug)
SELECT ROUND(100.0 * SUM(p.tot_drug_cst) FILTER (WHERE g.drug_group <> 'Other / unmapped')
             / SUM(p.tot_drug_cst), 1)                         AS pct_spend_mapped,
       ROUND(100.0 * SUM(p.tot_clms) FILTER (WHERE g.drug_group <> 'Other / unmapped')
             / SUM(p.tot_clms), 1)                             AS pct_claims_mapped,
       COUNT(DISTINCT p.gnrc_name) FILTER (WHERE g.drug_group <> 'Other / unmapped')
                                                               AS molecules_mapped
FROM prescriber_drug p
JOIN molecule_group g USING (gnrc_name)
WHERE p.data_year = (SELECT yr FROM latest);


-- name: q7_spend_by_group
-- Q7. Which therapeutic groups drive spend and growth? Latest year vs prior year.
WITH g AS (
    SELECT m.therapeutic_area, m.drug_group, p.data_year,
           SUM(p.tot_clms) AS claims, SUM(p.tot_drug_cst) AS cost
    FROM prescriber_drug p
    JOIN molecule_group m USING (gnrc_name)
    GROUP BY 1, 2, 3
),
w AS (
    SELECT *,
           LAG(cost)   OVER (PARTITION BY drug_group ORDER BY data_year) AS prior_cost,
           LAG(claims) OVER (PARTITION BY drug_group ORDER BY data_year) AS prior_claims,
           cost / SUM(cost) OVER (PARTITION BY data_year)                AS share
    FROM g
)
SELECT therapeutic_area, drug_group,
       ROUND(cost / 1e6, 1)                         AS cost_musd,
       ROUND(100 * share, 1)                        AS pct_of_spend,
       ROUND((cost - prior_cost) / 1e6, 1)          AS change_musd,
       ROUND(100 * (cost / prior_cost - 1), 1)      AS pct_cost_growth,
       ROUND(100 * (claims::NUMERIC / prior_claims - 1), 1) AS pct_claims_growth
FROM w
WHERE data_year = (SELECT MAX(data_year) FROM prescriber_drug)
ORDER BY cost DESC
LIMIT 20;
