#Creating Risk and Reliability Adjustment Using Aggegrated Data and a Bayesian Hierachical Model
library(glmmTMB)
library(arrow)
library(marginaleffects)
library(MetBrewer)
library(brms)
library(rstanarm)
library(ggpubr)

#Setup
site <- "Hopkins"
project_location <- '~/workspace/Storage/chochbe1/JH_CCRD/CLIF/CLIF_Projects/CLIF_prone_incidence'

#Load Data and Make Study Period and Gender Variables
#NOTE: This Table is Created by the 
prone_analytic_df <- open_dataset(paste0(project_location, '/project_tables/prone_analytic_data.parquet')) |>
  collect() |>
  mutate(female=fifelse(tolower(sex_category)=='female', 1, 0)) |>
  #Define Calendar Time for Time of Enrollment
  mutate(year=year(t_enrollment)) |>
  mutate(calendar_month=month(t_enrollment)) |>
  arrange(year, calendar_month) 

#Study Months
#Create a Study Month Data Frame to Merge to Create Study Month; Can Adjust ym() to accommodate desired period; for this analysis 2018 through 2024
study_month <- data.frame(start_date=seq(ym("201801"), ym("202412"), by= "months")) |>
  mutate(calendar_month=month(start_date)) |>
  mutate(year=year(start_date)) |>
  arrange(year, calendar_month) |>
  mutate(study_month=seq(1:n())) |>
  select(-start_date) |>
  mutate(study_quarter=ceiling(study_month/3))
prone_analytic_df <- prone_analytic_df |>
  left_join(study_month) 

#Define the Pre-Specified Study Periods
#Jan 2018-Feb 2020 'Pre-COVID', March 2020-February 2022 'COVID', March 2022-December 2023 'Post_COVID'
#So that All Sites Can Participate Will use the COVID Period as The Reference
prone_analytic_df <- prone_analytic_df |>
  mutate(study_period=fcase(
    study_month>=1 & study_month<27, 'Pre-COVID',
    study_month>=27 & study_month<51, 'COVID',
    study_month>=51, 'Post-COVID'
  )) |>
  mutate(study_period_cat=factor(study_period,
                                 levels = c("COVID", "Pre-COVID", "Post-COVID"),
                                 labels = c(1, 2, 3)))

#EACH SITE WOULD CREATE SITE-SPECIFIC PROPENSITY SCORES
#Generate Prone Propensity Score (Don't Account for Hospital or Study Period Here)
alt_form <- prone_12hour_outcome ~ age_at_admission  + female +
  bmi + factor(max_norepi_equivalent) + or_before_enrollment + min_pf_ratio
alt_mod <- glm(alt_form,
               data = prone_analytic_df, 
               family=binomial)
df <- alt_mod$data
#Propensity Score Taken from Prediction
df$prone_propensity <- predict(alt_mod, newdata=df, type = 'response')

#Each SIte Aggregates Data
#Create Aggregate Dataset with Observed and Expected Events as well as N
df_agg <- df |>
  group_by(hospital_id, study_period) |>
  summarise(
    n_patients = n(),
    observed_prone = sum(prone_12hour_outcome, na.rm=TRUE),
    prone_rate_observed = mean(prone_12hour_outcome, na.rm=TRUE),
    prone_rate_adjust = mean(prone_propensity, na.rm = TRUE)
  ) |>
  ungroup() |>
  filter(!is.na(hospital_id)) |>
  mutate(expected_prone=round((prone_rate_adjust*n_patients), digits = 0)) |>
  mutate(not_prone=n_patients-observed_prone) |>
  mutate(expected_prone_scaled=expected_prone-mean(expected_prone)) |>
  #Filter OUT HOspitals-Periods with < 10 observations - Will do this on the Analytic Side
  filter(n_patients>=10)

###ALL the code above is only to be run within each site. The 'df_agg' table which is aggregate summary data of observed and expected prone counts will be what's used in the rest of this script
###The Following Would be Done on Aggregate Data Only
#Now For the Bayesian Hierarchial Model
set.seed(32284)
priors <-c(
  prior(normal(0, 1), class = "b"), #Weakly Informative Prior
  prior(exponential(0.25), class = "sd") #Expect Variation Amongst Hospitals
)
agg_brm <- brm(
  bf(observed_prone | trials(n_patients) ~ 
       0 + expected_prone_scaled + study_period + (1 | hospital_id)), #NOTE: ~ 0 here models without intercept so each study_period has same amount of uncertainty
  data=df_agg,
  family=binomial,
  prior = priors, 
  cores = 4)

####Predictions Command from Marginal Effects with 4000 posterior draws
###This is Preferred 
reliability_adjust <- predictions(agg_brm, type = 'response', ndraws=4000, re_formula =  ~ (1 |hospital_id))
reliability_adjust <- as_tibble(reliability_adjust) |>
  mutate(adjust_rate=estimate/n_patients) |>
  mutate(ci_low=conf.low/n_patients) |>
  mutate(ci_hi=conf.high/n_patients) |>
  mutate(period_rank=fcase(
    study_period=='Pre-COVID', 0, 
    study_period=='COVID', 1, 
    study_period=='Post-COVID', 2
  )) |>
  #Orders for Graph
  arrange(period_rank, adjust_rate) |>
  mutate(hospital_rank=row_number())

risk_reliable_bayes <- ggplot(reliability_adjust, 
                        aes(x = hospital_rank,
                            y = adjust_rate)) +
  geom_line(aes(x = hospital_rank,
                y = adjust_rate, group=study_period), color='lightgrey') +
  geom_linerange(aes(ymin = ci_low, ymax = ci_hi, color= study_period)) +
  geom_point() +  # Add points for center effects
  scale_x_continuous(
    breaks = seq(1, nrow(reliability_adjust), by=1), 
    labels = NULL  # Optionally use hospital IDs as labels
  ) +
  scale_y_continuous(breaks=seq(0,0.65, by=0.1), 
                     labels = scales::percent, 
                     limits = c(0,0.65)) +
  MetBrewer::scale_color_met_d("Hokusai3") + #MetBrewer has many pallettes to choose from
  labs(
    title = "Risk and Reliability Adjusted Proning Rates - Bayesian Hierachical Model",
    x = "Hospital Rank",
    y = "Proned Within 12 Hours",
    caption = "Error bars represent 95% confidence intervals"
  )  +
  theme_minimal()

##Alternatively Don't Need to Use Bayesian Model Can Used Mixed Effects Logistic Regression
#I don't think predictions from marginal effects does not incorporate uncertainty in the random effects, and hence I don't think appropriate
#Now Use Standard Mixed Effects Aggregate Logisitic Regression Approach
agg_log <- glmmTMB(
  cbind(observed_prone, not_prone) ~ expected_prone_scaled + study_period + (1 | hospital_id), 
  data=df_agg,
  family=binomial
)

reliability_adjust_glmm <- predictions(agg_log, type = 'response', re_formula =  ~ (1 |hospital_id))
reliability_adjust_glmm <- as_tibble(reliability_adjust_glmm) |>
  mutate(period_rank=fcase(
    study_period=='Pre-COVID', 0, 
    study_period=='COVID', 1, 
    study_period=='Post-COVID', 2
  )) |>
  #Orders for Graph
  arrange(period_rank, estimate) |>
  mutate(hospital_rank=row_number())

#Graph
risk_reliable_glmm <- ggplot(reliability_adjust_glmm, 
                              aes(x = hospital_rank,
                                  y = estimate)) +
  geom_line(aes(x = hospital_rank,
                y = estimate, group=study_period), color='lightgrey') +
  geom_linerange(aes(ymin = conf.low, ymax = conf.high, color= study_period)) +
  geom_point() +  # Add points for center effects
  scale_x_continuous(
    breaks = seq(1, nrow(reliability_adjust_glmm), by=1), 
    labels = NULL  # Optionally use hospital IDs as labels
  ) +
  scale_y_continuous(breaks=seq(0,0.65, by=0.1), 
                     labels = scales::percent, 
                     limits = c(0,0.65)) +
  MetBrewer::scale_color_met_d("Hokusai3") + #MetBrewer has many pallettes to choose from
  labs(
    title = "Risk and Reliability Adjusted Proning Rates - GLMM Model",
    x = "Hospital Rank",
    y = "Proned Within 12 Hours",
    caption = "Error bars represent 95% confidence intervals"
  )  +
  theme_minimal()

#Put Graphs Side by Side
bayes <- risk_reliable_bayes + ggtitle('Bayesian Hierarchical')
rr_glm <- risk_reliable_glmm + ggtitle('Standard Mixed Effects')
ggarrange(bayes, rr_glm, ncol=2, common.legend = TRUE, legend="right")

#Add the Actual Value
bayes <- bayes +
  geom_point(aes(y=observed_prone/n_patients), color = 'red', alpha = 0.75)
