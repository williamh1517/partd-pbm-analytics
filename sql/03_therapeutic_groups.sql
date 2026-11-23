-- 03_therapeutic_groups.sql
-- Map each molecule (generic name) to a therapeutic group, then look at spend by group.
--
-- Design: a lookup table of LIKE patterns, matched against the lower-cased generic name.
-- `priority` breaks ties for combination products (e.g. sacubitril/valsartan is heart
-- failure, not an ARB; empagliflozin/metformin is an SGLT2 inhibitor, not metformin).
-- Lower number = checked first. Unmatched molecules fall into 'Other / unmapped', and
-- the share of spend that is mapped is reported so the reader knows the coverage.
-- A production version would use a standard classification (e.g. USP or ATC via RxNorm);
-- a hand-built list keeps this project self-contained and readable.

DROP TABLE IF EXISTS drug_group_map CASCADE;
CREATE TABLE drug_group_map (
    pattern          TEXT PRIMARY KEY,   -- LIKE pattern on LOWER(gnrc_name)
    drug_group       TEXT NOT NULL,
    therapeutic_area TEXT NOT NULL,
    priority         SMALLINT NOT NULL DEFAULT 50
);

INSERT INTO drug_group_map (pattern, drug_group, therapeutic_area, priority) VALUES
-- Diabetes (checked before cardio so combos land here)
('%insulin%',        'Insulins',                 'Diabetes', 10),
('%tirzepatide%',    'GLP-1 / GIP agonists',     'Diabetes', 11),
('%semaglutide%',    'GLP-1 / GIP agonists',     'Diabetes', 11),
('%dulaglutide%',    'GLP-1 / GIP agonists',     'Diabetes', 11),
('%liraglutide%',    'GLP-1 / GIP agonists',     'Diabetes', 11),
('%exenatide%',      'GLP-1 / GIP agonists',     'Diabetes', 11),
('%empagliflozin%',  'SGLT2 inhibitors',         'Diabetes', 12),
('%dapagliflozin%',  'SGLT2 inhibitors',         'Diabetes', 12),
('%canagliflozin%',  'SGLT2 inhibitors',         'Diabetes', 12),
('%ertugliflozin%',  'SGLT2 inhibitors',         'Diabetes', 12),
('%sitagliptin%',    'DPP-4 inhibitors',         'Diabetes', 13),
('%linagliptin%',    'DPP-4 inhibitors',         'Diabetes', 13),
('%saxagliptin%',    'DPP-4 inhibitors',         'Diabetes', 13),
('%alogliptin%',     'DPP-4 inhibitors',         'Diabetes', 13),
('%metformin%',      'Metformin & other oral',   'Diabetes', 14),
('%glipizide%',      'Metformin & other oral',   'Diabetes', 14),
('%glimepiride%',    'Metformin & other oral',   'Diabetes', 14),
('%glyburide%',      'Metformin & other oral',   'Diabetes', 14),
('%pioglitazone%',   'Metformin & other oral',   'Diabetes', 14),
-- Cardiovascular
('%sacubitril%',     'Heart failure (ARNI)',     'Cardiovascular', 20),
('%apixaban%',       'Anticoagulants',           'Cardiovascular', 21),
('%rivaroxaban%',    'Anticoagulants',           'Cardiovascular', 21),
('%dabigatran%',     'Anticoagulants',           'Cardiovascular', 21),
('%edoxaban%',       'Anticoagulants',           'Cardiovascular', 21),
('%warfarin%',       'Anticoagulants',           'Cardiovascular', 21),
('%clopidogrel%',    'Antiplatelets',            'Cardiovascular', 22),
('%ticagrelor%',     'Antiplatelets',            'Cardiovascular', 22),
('%prasugrel%',      'Antiplatelets',            'Cardiovascular', 22),
('%atorvastatin%',   'Statins & lipid',          'Cardiovascular', 23),
('%rosuvastatin%',   'Statins & lipid',          'Cardiovascular', 23),
('%simvastatin%',    'Statins & lipid',          'Cardiovascular', 23),
('%pravastatin%',    'Statins & lipid',          'Cardiovascular', 23),
('%lovastatin%',     'Statins & lipid',          'Cardiovascular', 23),
('%pitavastatin%',   'Statins & lipid',          'Cardiovascular', 23),
('%ezetimibe%',      'Statins & lipid',          'Cardiovascular', 23),
('%icosapent%',      'Statins & lipid',          'Cardiovascular', 23),
('%evolocumab%',     'Statins & lipid',          'Cardiovascular', 23),
('%alirocumab%',     'Statins & lipid',          'Cardiovascular', 23),
('%tafamidis%',      'Cardiomyopathy',           'Cardiovascular', 24),
('%mavacamten%',     'Cardiomyopathy',           'Cardiovascular', 24),
('%lisinopril%',     'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%enalapril%',      'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%benazepril%',     'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%ramipril%',       'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%quinapril%',      'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%losartan%',       'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%valsartan%',      'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%olmesartan%',     'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%irbesartan%',     'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%telmisartan%',    'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%candesartan%',    'ACE inhibitors / ARBs',    'Cardiovascular', 25),
('%metoprolol%',     'Beta blockers',            'Cardiovascular', 26),
('%carvedilol%',     'Beta blockers',            'Cardiovascular', 26),
('%atenolol%',       'Beta blockers',            'Cardiovascular', 26),
('%bisoprolol%',     'Beta blockers',            'Cardiovascular', 26),
('%propranolol%',    'Beta blockers',            'Cardiovascular', 26),
('%nebivolol%',      'Beta blockers',            'Cardiovascular', 26),
('%amlodipine%',     'Calcium channel blockers', 'Cardiovascular', 27),
('%nifedipine%',     'Calcium channel blockers', 'Cardiovascular', 27),
('%diltiazem%',      'Calcium channel blockers', 'Cardiovascular', 27),
('%verapamil%',      'Calcium channel blockers', 'Cardiovascular', 27),
('%furosemide%',     'Diuretics',                'Cardiovascular', 28),
('%torsemide%',      'Diuretics',                'Cardiovascular', 28),
('%bumetanide%',     'Diuretics',                'Cardiovascular', 28),
('%hydrochlorothiazide%', 'Diuretics',           'Cardiovascular', 28),
('%chlorthalidone%', 'Diuretics',                'Cardiovascular', 28),
('%spironolactone%', 'Diuretics',                'Cardiovascular', 28),
('%ranolazine%',     'Other cardiovascular',     'Cardiovascular', 29),
('%amiodarone%',     'Other cardiovascular',     'Cardiovascular', 29),
-- Respiratory
('%tiotropium%',     'Inhaled COPD / asthma',    'Respiratory', 30),
('%umeclidinium%',   'Inhaled COPD / asthma',    'Respiratory', 30),
('%fluticasone%',    'Inhaled COPD / asthma',    'Respiratory', 30),
('%budesonide%',     'Inhaled COPD / asthma',    'Respiratory', 30),
('%albuterol%',      'Inhaled COPD / asthma',    'Respiratory', 30),
('%formoterol%',     'Inhaled COPD / asthma',    'Respiratory', 30),
('%salmeterol%',     'Inhaled COPD / asthma',    'Respiratory', 30),
('%ipratropium%',    'Inhaled COPD / asthma',    'Respiratory', 30),
('%mometasone%',     'Inhaled COPD / asthma',    'Respiratory', 30),
('%beclomethasone%', 'Inhaled COPD / asthma',    'Respiratory', 30),
('%montelukast%',    'Inhaled COPD / asthma',    'Respiratory', 30),
('%roflumilast%',    'Inhaled COPD / asthma',    'Respiratory', 30),
('%elexacaftor%',    'Cystic fibrosis',          'Respiratory', 31),
('%nintedanib%',     'Pulmonary fibrosis',       'Respiratory', 31),
('%pirfenidone%',    'Pulmonary fibrosis',       'Respiratory', 31),
-- Oncology (oral)
('%ibrutinib%',      'Oral oncology',            'Oncology', 40),
('%acalabrutinib%',  'Oral oncology',            'Oncology', 40),
('%zanubrutinib%',   'Oral oncology',            'Oncology', 40),
('%lenalidomide%',   'Oral oncology',            'Oncology', 40),
('%pomalidomide%',   'Oral oncology',            'Oncology', 40),
('%palbociclib%',    'Oral oncology',            'Oncology', 40),
('%ribociclib%',     'Oral oncology',            'Oncology', 40),
('%abemaciclib%',    'Oral oncology',            'Oncology', 40),
('%enzalutamide%',   'Oral oncology',            'Oncology', 40),
('%abiraterone%',    'Oral oncology',            'Oncology', 40),
('%apalutamide%',    'Oral oncology',            'Oncology', 40),
('%darolutamide%',   'Oral oncology',            'Oncology', 40),
('%olaparib%',       'Oral oncology',            'Oncology', 40),
('%osimertinib%',    'Oral oncology',            'Oncology', 40),
('%venetoclax%',     'Oral oncology',            'Oncology', 40),
('%ruxolitinib%',    'Oral oncology',            'Oncology', 40),
('%imatinib%',       'Oral oncology',            'Oncology', 40),
('%dasatinib%',      'Oral oncology',            'Oncology', 40),
('%nilotinib%',      'Oral oncology',            'Oncology', 40),
('%capecitabine%',   'Oral oncology',            'Oncology', 40),
('%cabozantinib%',   'Oral oncology',            'Oncology', 40),
('%lenvatinib%',     'Oral oncology',            'Oncology', 40),
('%anastrozole%',    'Oral oncology',            'Oncology', 40),
('%letrozole%',      'Oral oncology',            'Oncology', 40),
('%tamoxifen%',      'Oral oncology',            'Oncology', 40),
('%exemestane%',     'Oral oncology',            'Oncology', 40),
-- Immunology & infectious disease
('%adalimumab%',     'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%etanercept%',     'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%ustekinumab%',    'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%secukinumab%',    'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%ixekizumab%',     'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%guselkumab%',     'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%risankizumab%',   'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%apremilast%',     'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%tofacitinib%',    'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%upadacitinib%',   'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%dupilumab%',      'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%methotrexate%',   'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%hydroxychloroquine%', 'Immunology (RA, psoriasis, IBD)', 'Immunology', 41),
('%bictegravir%',    'HIV',                      'Infectious disease', 42),
('%dolutegravir%',   'HIV',                      'Infectious disease', 42),
('%emtricitabine%',  'HIV',                      'Infectious disease', 42),
('%darunavir%',      'HIV',                      'Infectious disease', 42),
('%rilpivirine%',    'HIV',                      'Infectious disease', 42),
('%cabotegravir%',   'HIV',                      'Infectious disease', 42),
('%abacavir%',       'HIV',                      'Infectious disease', 42),
('%raltegravir%',    'HIV',                      'Infectious disease', 42),
('%sofosbuvir%',     'Hepatitis C',              'Infectious disease', 42),
('%glecaprevir%',    'Hepatitis C',              'Infectious disease', 42),
('%entecavir%',      'Hepatitis B',              'Infectious disease', 42),
('%vac%',            'Vaccines',                 'Infectious disease', 43),
('%valacyclovir%',   'Antivirals',               'Infectious disease', 44),
('%acyclovir%',      'Antivirals',               'Infectious disease', 44),
('%oseltamivir%',    'Antivirals',               'Infectious disease', 44),
('%nirmatrelvir%',   'Antivirals',               'Infectious disease', 44),
('%amoxicillin%',    'Antibiotics',              'Infectious disease', 45),
('%cephalexin%',     'Antibiotics',              'Infectious disease', 45),
('%azithromycin%',   'Antibiotics',              'Infectious disease', 45),
('%doxycycline%',    'Antibiotics',              'Infectious disease', 45),
('%ciprofloxacin%',  'Antibiotics',              'Infectious disease', 45),
('%levofloxacin%',   'Antibiotics',              'Infectious disease', 45),
('%nitrofurantoin%', 'Antibiotics',              'Infectious disease', 45),
('%sulfamethoxazole%','Antibiotics',             'Infectious disease', 45),
('%cefdinir%',       'Antibiotics',              'Infectious disease', 45),
('%rifaximin%',      'Antibiotics',              'Infectious disease', 45),
-- Neurology & mental health
('%buprenorphine%',  'Opioid use disorder',      'Neurology & mental health', 50),
('%naltrexone%',     'Opioid use disorder',      'Neurology & mental health', 50),
('%oxycodone%',      'Opioid analgesics',        'Neurology & mental health', 51),
('%hydrocodone%',    'Opioid analgesics',        'Neurology & mental health', 51),
('%tramadol%',       'Opioid analgesics',        'Neurology & mental health', 51),
('%morphine%',       'Opioid analgesics',        'Neurology & mental health', 51),
('%hydromorphone%',  'Opioid analgesics',        'Neurology & mental health', 51),
('%fentanyl%',       'Opioid analgesics',        'Neurology & mental health', 51),
('%methadone%',      'Opioid analgesics',        'Neurology & mental health', 51),
('%tapentadol%',     'Opioid analgesics',        'Neurology & mental health', 51),
('%sertraline%',     'Antidepressants',          'Neurology & mental health', 52),
('%escitalopram%',   'Antidepressants',          'Neurology & mental health', 52),
('%citalopram%',     'Antidepressants',          'Neurology & mental health', 52),
('%fluoxetine%',     'Antidepressants',          'Neurology & mental health', 52),
('%paroxetine%',     'Antidepressants',          'Neurology & mental health', 52),
('%trazodone%',      'Antidepressants',          'Neurology & mental health', 52),
('%bupropion%',      'Antidepressants',          'Neurology & mental health', 52),
('%duloxetine%',     'Antidepressants',          'Neurology & mental health', 52),
('%venlafaxine%',    'Antidepressants',          'Neurology & mental health', 52),
('%mirtazapine%',    'Antidepressants',          'Neurology & mental health', 52),
('%vortioxetine%',   'Antidepressants',          'Neurology & mental health', 52),
('%quetiapine%',     'Antipsychotics',           'Neurology & mental health', 53),
('%aripiprazole%',   'Antipsychotics',           'Neurology & mental health', 53),
('%olanzapine%',     'Antipsychotics',           'Neurology & mental health', 53),
('%risperidone%',    'Antipsychotics',           'Neurology & mental health', 53),
('%lurasidone%',     'Antipsychotics',           'Neurology & mental health', 53),
('%brexpiprazole%',  'Antipsychotics',           'Neurology & mental health', 53),
('%cariprazine%',    'Antipsychotics',           'Neurology & mental health', 53),
('%paliperidone%',   'Antipsychotics',           'Neurology & mental health', 53),
('%clozapine%',      'Antipsychotics',           'Neurology & mental health', 53),
('%valbenazine%',    'Movement disorders',       'Neurology & mental health', 54),
('%deutetrabenazine%','Movement disorders',      'Neurology & mental health', 54),
('%carbidopa%',      'Movement disorders',       'Neurology & mental health', 54),
('%donepezil%',      'Dementia',                 'Neurology & mental health', 55),
('%memantine%',      'Dementia',                 'Neurology & mental health', 55),
('%rivastigmine%',   'Dementia',                 'Neurology & mental health', 55),
('%levetiracetam%',  'Anticonvulsants',          'Neurology & mental health', 56),
('%lamotrigine%',    'Anticonvulsants',          'Neurology & mental health', 56),
('%lacosamide%',     'Anticonvulsants',          'Neurology & mental health', 56),
('%topiramate%',     'Anticonvulsants',          'Neurology & mental health', 56),
('%oxcarbazepine%',  'Anticonvulsants',          'Neurology & mental health', 56),
('%carbamazepine%',  'Anticonvulsants',          'Neurology & mental health', 56),
('%divalproex%',     'Anticonvulsants',          'Neurology & mental health', 56),
('%gabapentin%',     'Gabapentinoids',           'Neurology & mental health', 57),
('%pregabalin%',     'Gabapentinoids',           'Neurology & mental health', 57),
('%rimegepant%',     'Migraine',                 'Neurology & mental health', 58),
('%ubrogepant%',     'Migraine',                 'Neurology & mental health', 58),
('%atogepant%',      'Migraine',                 'Neurology & mental health', 58),
('%sumatriptan%',    'Migraine',                 'Neurology & mental health', 58),
('%erenumab%',       'Migraine',                 'Neurology & mental health', 58),
('%galcanezumab%',   'Migraine',                 'Neurology & mental health', 58),
('%dimethyl fumarate%','Multiple sclerosis',     'Neurology & mental health', 59),
('%fingolimod%',     'Multiple sclerosis',       'Neurology & mental health', 59),
('%teriflunomide%',  'Multiple sclerosis',       'Neurology & mental health', 59),
('%glatiramer%',     'Multiple sclerosis',       'Neurology & mental health', 59),
('%ozanimod%',       'Multiple sclerosis',       'Neurology & mental health', 59),
('%siponimod%',      'Multiple sclerosis',       'Neurology & mental health', 59),
-- Other common classes
('%pantoprazole%',   'Acid reducers',            'Gastrointestinal', 60),
('%omeprazole%',     'Acid reducers',            'Gastrointestinal', 60),
('%lansoprazole%',   'Acid reducers',            'Gastrointestinal', 60),
('%rabeprazole%',    'Acid reducers',            'Gastrointestinal', 60),
('%famotidine%',     'Acid reducers',            'Gastrointestinal', 60),
('%linaclotide%',    'Other GI',                 'Gastrointestinal', 61),
('%mesalamine%',     'Other GI',                 'Gastrointestinal', 61),
('%levothyroxine%',  'Thyroid',                  'Endocrine & other', 62),
('%liothyronine%',   'Thyroid',                  'Endocrine & other', 62),
('%alendronate%',    'Osteoporosis',             'Endocrine & other', 63),
('%denosumab%',      'Osteoporosis',             'Endocrine & other', 63),
('%teriparatide%',   'Osteoporosis',             'Endocrine & other', 63),
('%allopurinol%',    'Gout',                     'Endocrine & other', 64),
('%febuxostat%',     'Gout',                     'Endocrine & other', 64),
('%colchicine%',     'Gout',                     'Endocrine & other', 64),
('%tamsulosin%',     'Urology',                  'Endocrine & other', 65),
('%finasteride%',    'Urology',                  'Endocrine & other', 65),
('%mirabegron%',     'Urology',                  'Endocrine & other', 65),
('%vibegron%',       'Urology',                  'Endocrine & other', 65),
('%oxybutynin%',     'Urology',                  'Endocrine & other', 65),
('%solifenacin%',    'Urology',                  'Endocrine & other', 65),
('%latanoprost%',    'Eye care',                 'Endocrine & other', 66),
('%timolol%',        'Eye care',                 'Endocrine & other', 66),
('%dorzolamide%',    'Eye care',                 'Endocrine & other', 66),
('%brimonidine%',    'Eye care',                 'Endocrine & other', 66),
('%netarsudil%',     'Eye care',                 'Endocrine & other', 66),
('%lifitegrast%',    'Eye care',                 'Endocrine & other', 66),
('%prednisone%',     'Corticosteroids',          'Endocrine & other', 67),
('%methylprednisolone%','Corticosteroids',       'Endocrine & other', 67),
('%dexamethasone%',  'Corticosteroids',          'Endocrine & other', 67),
('%sevelamer%',      'Kidney disease',           'Endocrine & other', 68),
('%finerenone%',     'Kidney disease',           'Endocrine & other', 68),
('%epoetin%',        'Kidney disease',           'Endocrine & other', 68);


-- The function a dashboard or other query calls: generic name in, therapeutic group out.
CREATE OR REPLACE FUNCTION fn_drug_group(p_gnrc_name TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT m.drug_group
         FROM drug_group_map m
         WHERE LOWER(p_gnrc_name) LIKE m.pattern
         ORDER BY m.priority, m.pattern
         LIMIT 1),
        'Other / unmapped');
$$;

CREATE OR REPLACE FUNCTION fn_therapeutic_area(p_gnrc_name TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT m.therapeutic_area
         FROM drug_group_map m
         WHERE LOWER(p_gnrc_name) LIKE m.pattern
         ORDER BY m.priority, m.pattern
         LIMIT 1),
        'Other / unmapped');
$$;

-- Molecule-level mapping, computed once (about 1,700 molecules) instead of once per row.
DROP TABLE IF EXISTS molecule_group;
CREATE TABLE molecule_group AS
SELECT gnrc_name,
       fn_drug_group(gnrc_name)       AS drug_group,
       fn_therapeutic_area(gnrc_name) AS therapeutic_area
FROM (SELECT DISTINCT gnrc_name FROM prescriber_drug) g;
ALTER TABLE molecule_group ADD PRIMARY KEY (gnrc_name);
