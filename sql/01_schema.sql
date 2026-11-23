-- 01_schema.sql
-- One row = one prescriber (NPI) x one drug (brand name + generic name) x one data year.
-- Source: CMS "Medicare Part D Prescribers - by Provider and Drug".
-- CMS drops any prescriber-drug row with fewer than 11 claims, and blanks out
-- beneficiary counts under 11, so small counts are missing by design.

DROP TABLE IF EXISTS prescriber_drug CASCADE;

CREATE TABLE prescriber_drug (
    data_year            SMALLINT     NOT NULL,
    prscrbr_npi          BIGINT       NOT NULL,
    prscrbr_last_org_name TEXT,
    prscrbr_first_name   TEXT,
    prscrbr_city         TEXT,
    prscrbr_state        CHAR(2)      NOT NULL,
    prscrbr_type         TEXT,          -- specialty, used as the peer group
    prscrbr_type_src     TEXT,
    brnd_name            TEXT         NOT NULL,
    gnrc_name            TEXT         NOT NULL,
    tot_clms             INTEGER      NOT NULL,  -- prescription fills, incl. refills
    tot_30day_fills      NUMERIC(12,1),          -- fills standardized to 30-day supplies
    tot_day_suply        INTEGER,
    tot_drug_cst         NUMERIC(14,2) NOT NULL, -- gross cost before manufacturer rebates
    tot_benes            INTEGER,                -- NULL when suppressed (<11)
    -- Brand flag. The CMS file has no brand/generic field, so it is derived from the names:
    -- a product is GENERIC when its brand name starts with the first word of the molecule name
    -- (e.g. 'Metformin Hcl Er' / 'Metformin Hcl', 'Insulin Lispro Kwikpen' / 'Insulin Lispro'),
    -- and BRAND otherwise (e.g. 'Eliquis' / 'Apixaban').
    -- Known limitation: "branded generics" sold under a trade name (e.g. 'Aviane',
    -- an oral contraceptive) count as brand. They are cheap, so cost results barely move.
    is_brand             BOOLEAN GENERATED ALWAYS AS (
                             NOT (UPPER(TRIM(brnd_name)) LIKE
                                  UPPER(SPLIT_PART(TRANSLATE(TRIM(gnrc_name), '/-', '  '), ' ', 1)) || '%')
                         ) STORED
);

COMMENT ON TABLE  prescriber_drug IS 'CMS Part D Prescribers by Provider and Drug, one state, several data years';
COMMENT ON COLUMN prescriber_drug.tot_drug_cst IS 'Gross drug cost paid (plan + patient + other), before rebates';
