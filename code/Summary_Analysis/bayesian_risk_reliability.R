#Creating Risk and Reliability Adjustment Using Aggegrated Data and a Bayesian Hierachical Model
library(glmmTMB)
library(marginaleffects)
library(MetBrewer)
library(brms)
library(rstanarm)
library(ggpubr)

#EACH SITE WOULD CREATE SITE-SPECIFIC PROPENSITY SCORES
#Generate Prone Propensity Score (Don't Account for Hospital or Study Period Here)
alt_form <- prone_12hour_outcome ~ age_at_admission  + 
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
  #Create Centered Expected_prone
  mutate(expected_prone_scaled=expected_prone-mean(expected_prone)) |>
  mutate(not_prone=n_patients-observed_prone) |>
  #Filter OUT HOspitals-Periods with < 10 observations - Will do this on the Analytic Side
  filter(n_patients>=10)
  

###The Following Would be Done on Aggregate Data Only
#Now For the Bayesian Hierarchial Model
set.seed(32284)
agg_brm <- brm(
  bf(observed_prone | trials(n_patients) ~ 
       expected_prone_scaled + study_period + (1 | hospital_id)),
  data=df_agg,
  family=binomial,
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
