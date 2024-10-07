#Code for Creating Encounter Block
clif_hospitalization <- clif_hospitalization |>
  filter(admission_dttm >= as.POSIXct(start_date, tz = "UTC") &
           admission_dttm <= as.POSIXct(end_date, tz = "UTC")) |>
  compute()

#Create an Hospital Block ID - This is to Identify Continuous Hospitalizations When Patients Are Transferred Between Hospitals in One Health System
#This code is intended be robust to various ways encounters may be coded in CLIF databases
hospital_blocks <- clif_hospitalization |>
  select(patient_id, hospitalization_id, admission_dttm, discharge_dttm) |>
  arrange(patient_id, admission_dttm) |>
  collect()

#Identify Admissions That Occur Within 3 Hours of a Discharge (Will Consider Those Linked and as Part of One Continuous Encounter)
#Use Data Table for Speed
linked_encounters <- setDT(hospital_blocks)
#Create a Variable for the time of the next admission and time of previous discharge
linked_encounters[, ':=' (next_admit_dttm = data.table::shift(admission_dttm, n=1, type = "lead")), by = patient_id]
linked_encounters[, ':=' (prev_dc_dttm = data.table::shift(discharge_dttm, n=1, type = "lag")), by = patient_id]
#Calculates Time Between Discharge and Next Admit
linked_encounters[, next_diff_time := difftime(next_admit_dttm, discharge_dttm, units = "hours")]
linked_encounters[, prev_diff_time := difftime(admission_dttm, prev_dc_dttm, units = "hours")]

#Now Create Variable Indicating a Linked Encounter (next_admit-dc time <6 hours or prev_dc-admint <6 hours)
linked_encounters[, linked := fcase(
  (next_diff_time <6 | prev_diff_time <6), 1)]
#Filter to Only Linked Encounters and number them
linked_encounters <- linked_encounters[linked==1]
#This Identifies the First Encounter in a Series of Linked Encounters
linked_encounters[, first_link := fcase(
  (rowid(linked)==1 | (next_diff_time<6 & prev_diff_time>6)), 1
), by = patient_id]
#Now Numbers Encounters, easier in dplyr
#Filter to Just First Links, Number them and then Remerge with linked encounters
temp <- as_tibble(linked_encounters) |>
  filter(first_link==1) |>
  group_by(patient_id) |>
  mutate(link_group=row_number()) |>
  ungroup() |>
  select(hospitalization_id, link_group) 
linked_encounters <- as_tibble(left_join(linked_encounters, temp)) |>
  fill(link_group, .direction = c("down")) |>
  #Create a Variable Indicating Which Number of LIinked Encounter the Encounter is
  group_by(patient_id, link_group) |>
  mutate(link_number=row_number()) |>
  ungroup() |>
  select(hospitalization_id, linked, link_number)
rm(temp)

#Now Join Back to Hospitalization Table
clif_hospitalization <- clif_hospitalization |>
  left_join(linked_encounters) |>
  mutate(linked=if_else(is.na(linked), 0, linked)) |>
  compute()

#Pull Out the Any Linked Encounter that Is NOt the First Encounter and Assign Each Encounter an Encounter Block ID in the Original clif_hospitalization table
df_link <- clif_hospitalization |>
  filter(link_number>1) |>
  collect()

clif_hospitalization <- clif_hospitalization |>
  group_by(patient_id) |>
  arrange(patient_id, admission_dttm) |>
  #Remove Link Numbers that Are Not First in Link Encounter
  filter(link_number==1 | is.na(link_number)) |>
  #Make Encounter Blocks
  collect() |>
  mutate(encounter_block=row_number()) |>
  rowbind(df_link, fill = TRUE) |> #Bring Back in Link Numbers >1
  group_by(patient_id) |> arrange(patient_id, admission_dttm) |>
  fill(encounter_block, .direction = "down") |>
  ungroup()|>
  #Finally, for Linked Encounters Identify 'Final_admit_date' and 'final_dc_date' which are the first and last dates of a link block
  group_by(patient_id, encounter_block) |>
  mutate(final_admission_dttm=fcase(
    row_number()==1, admission_dttm
  )) |>
  mutate(final_discharge_dttm=fcase(
    row_number()==n(), discharge_dttm
  )) |>
  fill(final_admission_dttm, final_discharge_dttm, .direction = 'updown') |>
  relocate(encounter_block, .after = 'hospitalization_id') |>
  as_arrow_table()
