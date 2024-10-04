#Multi-center Evaluation of Prone Positioning Practices for Severe Respiratory Failure

## Objective

Evaluate the Incidence of Prone Positioning for Patients with Severe Hypoxemic Respiratory Failure Over Time Using the Common Longitudinal ICU Format (CLIF)

## Required CLIF tables and fields

Please refer to the online [CLIF data dictionary](https://clif-consortium.github.io/website/data-dictionary.html), [ETL tools](https://github.com/clif-consortium/CLIF/tree/main/etl-to-clif-resources), and [specific table contacts](https://github.com/clif-consortium/CLIF?tab=readme-ov-file#relational-clif) for more information on constructing the required tables and fields. List all required tables for the project here, and provide a brief rationale for why they are required.


The following tables are required:
1. **patient**: `patient_id`, `race_category`, `ethnicity_category`, `sex_category`
2. **hospitalization**: `patient_id`, `hospitalization_id`, `admission_dttm`, `discharge_dttm`, `age_at_admission`
3. **vitals**: `hospitalization_id`, `recorded_dttm`, `vital_category`, `vital_value`
   - `vital_category` = 'heart_rate', 'resp_rate', 'sbp', 'dbp', 'map', 'resp_rate', 'spo2'
4. **labs**: `hospitalization_id`, `lab_result_dttm`, `lab_category`, `lab_value`
   - `lab_category` = 'lactate'
5. **medication_admin_continuous**: `hospitalization_id`, `admin_dttm`, `med_name`, `med_category`, `med_dose`, `med_dose_unit`
   - `med_category` = "norepinephrine", "epinephrine", "phenylephrine", "vasopressin", "dopamine", "angiotensin", "nicardipine", "nitroprusside", "clevidipine", "cisatracurium"
6. **respiratory_support**: `hospitalization_id`, `recorded_dttm`, `device_category`, `mode_category`, `tracheostomy`, `fio2_set`, `lpm_set`, `resp_rate_set`, `peep_set`, `resp_rate_obs`


## Cohort identification
Inclusion Criteria: 
1)	Adults (> 18 years) with moderate-severe hypoxemic respiratory failure requiring invasive mechanical ventilation (IMV) between 2018-2023 (NOTE: Not all sites may have full range of data, but will use the years of each database)

2)	Patient meets PROSEVA criteria for proning defined as: 
a.	P/F < 150 on PEEP > 5 and FiO2 > 0.6 (uses ABG measurements only, no imputation)
b.	Criteria are met in the first 36 hours of IMV initiation (t_PROSEVA_first)
      AND
i.	Confirmed on second qualifying blood gas in a 12-hour window beginning 12 hours after the first eligible blood gas (t_proseva_first + 12 hours > t_proseva_second < t_proseva_first + 24 hours)
                   OR
ii.	Patient is proned within 24 hours of initial qualifying blood gas (t_PROSEVA_first < t_proning < t_PROSEVA_first + 24 hours)

3)	For patients meeting the above inclusions, time of enrollment (t_enrollment) is the earlier of time of second qualifying PROSEVA ABG OR time of proning (if patient proned prior to meeting criteria second time). 


Exclusion Criteria: 
1)	Mechanical ventilation initiated at outside hospital:
a.	Operationalization: 
i.	OPTION A: If a patient’s first ADT observation is not the ED (location_category!=’ED’) AND first device_category==’IMV’ exclude
ii.	OPTION B: Use admission_category!=’Transfer’ [syntax not yet in CLIF]
2)	First airway ventilator observation is with a tracheostomy
3)	On ECMO within 12-hours of t_enrollment [Will work into future iterations of project once ECMO table built]
4)	For patients with more than 1 eligible encounter within a given CLIF consortium system, 1 eligible encounter per patient will be randomly selected and included

## Expected Results

Describe the output of the analysis. The final project results should be saved in the [`output/final`](output/README.md) directory.

## Detailed Instructions for running the project

## 1. Setup Project Environment
Describe the steps to setup the project environment. 

Example for R:
```
# Setup R environment using renv
# Install renv if not already installed:
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
# Initialize renv for the project:
renv::init()
# Install required packages:
renv::install(c("knitr", "here", "tidyverse", "arrow", "gtsummary"))
# Save the project's package state:
renv::snapshot()
```

Example for Python:
```
python3 -m venv .mobilization
source .mobilization/bin/activate
pip install -r requirements.txt 
```

## 2. Update `config/config.json`
Follow instructions in the [config/README.md](config/README.md) file for detailed configuration steps.

## 3. Run code
Detailed instructions on the code workflow are provided in the [code directory](code/README.md)


## Example Repositories
* [CLIF Adult Sepsis Events](https://github.com/08wparker/CLIF_adult_sepsis_events) for R
* [CLIF Eligibility for mobilization](https://github.com/kaveriC/mobilization) for Python
---


