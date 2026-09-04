# Examining Socio-Economic Disparities in Math, Reading, and Science Skills
# An International Comparison using PISA 2022 Dataset

# The Programme for International Student Assessment (PISA) is an international
# study conducted by the OECD that evaluates education systems worldwide by
# testing 15-year-old students in reading, mathematics, and science every four
# years. This project analyzes the relationship between socioeconomic status
# (SES) and academic performance using the PISA 2022 dataset
# (N = 613,744 students across 80 countries).


library(haven)
library(stringr)
library(tidyverse)

# 1. Data Preprocessing

# 1.1 Dataset Preparation
# The PISA 2022 Student Questionnaire was downloaded as a single SPSS file
# (~1.95GB) from the OECD website and converted to RDS format for faster
# loading in R. It includes academic scores, socioeconomic indicators, and
# 42 survey items related to home and family background.

message("Started reading file: ", Sys.time())
pisa <- read_sav("data/CY08MSP_STU_QQQ.SAV")
message("Finished reading: ", Sys.time())

saveRDS(pisa, "data/pisa2022sq.rds")
pisa <- readRDS("data/pisa2022sq.rds")

# 1.2 Variables Preparation
# ESCS (Index of Economic, Social, and Cultural Status) represents students'
# socioeconomic status, derived from 42 survey questions. Academic scores were
# computed by averaging ten plausible values (PV1-PV10) for each subject.
# A subset was created containing ESCS, averaged scores, 42 SES survey items,
# and country/student identifiers.

# Compute mean scores across 10 plausible values
pisa$MATHH <- rowMeans(pisa[, paste0("PV", 1:10, "MATH")])
pisa$READD <- rowMeans(pisa[, paste0("PV", 1:10, "READ")])
pisa$SCIEE <- rowMeans(pisa[, paste0("PV", 1:10, "SCIE")])

# Verify no missing values in plausible values
sum(is.na(pisa[, c(paste0("PV", 1:10, "MATH"), paste0("PV", 1:10, "READ"), paste0("PV", 1:10, "SCIE"))]))

# Select relevant columns
question_columns <- colnames(pisa) %>%
  str_subset("^ST(250|251|253|254|255|256|005|006|007|008|258|259)Q.*")

variables <- pisa %>%
  select(CNT, CNTRYID, CNTSTUID, ESCS, MATHH, SCIEE, READD, all_of(question_columns))

# Missing ESCS values were imputed using country-level means.
# Costa Rica was excluded due to entirely missing ESCS data.
# Survey items ST254 and ST256 used a non-sequential coding scheme
# where 5 = "I don't know" — these were recoded to 0.

# Impute missing ESCS with country mean
variables <- variables %>%
  group_by(CNT) %>%
  mutate(ESCS = ifelse(is.na(ESCS), mean(ESCS, na.rm = TRUE), ESCS)) %>%
  ungroup() %>%
  filter(CNT != "CRI")

# Recode "I don't know" to 0
variables <- variables %>%
  mutate(across(matches("^ST(254|256)Q.*"), ~ ifelse(. == 5, 0, .)))

# Students missing more than 14 of 42 survey responses were excluded,
# retaining 90% of the dataset. Remaining missing values were imputed
# with country-level question means.

variables$NA_count <- rowSums(is.na(variables))

ggplot(variables, aes(x = NA_count)) +
  geom_histogram(binwidth = 1, fill = "blue", color = "black") +
  labs(title = "Distribution of Missing Answers per Student",
       x = "Number of NAs", y = "Frequency")

total_students <- nrow(variables)
retention <- sapply(1:42, function(threshold) {
  sum(variables$NA_count <= threshold) / total_students * 100
})
retention_variables <- data.frame(Threshold = 1:42, Retention_Percentage = retention)

ggplot(retention_variables, aes(x = Threshold, y = Retention_Percentage)) +
  geom_line() + geom_point() +
  labs(title = "Retention Percentage vs Threshold",
       x = "Threshold (Number of NAs Allowed)",
       y = "Retention Percentage") +
  theme_minimal()

threshold <- 14
filtered_variables <- variables %>%
  filter(NA_count <= threshold) %>%
  select(-NA_count)

imputed_variables <- filtered_variables %>%
  group_by(CNT) %>%
  mutate(across(everything(), ~ replace(., is.na(.) | is.nan(.),
                                         coalesce(mean(., na.rm = TRUE), 0)))) %>%
  ungroup()

sum(is.na(imputed_variables))

# 2. Exploratory Data Analysis (EDA)
# Summary statistics (min, Q1, median, mean, Q3, max, SD) were calculated for
# ESCS, math, reading, and science scores across all 79 countries.
# Correlation between key variables was also examined.

country_summary <- imputed_variables %>%
  group_by(CNT) %>%
  summarise(
    across(
      c(ESCS, MATHH, READD, SCIEE),
      list(
        Min    = ~min(., na.rm = TRUE),
        Q1     = ~quantile(., 0.25, na.rm = TRUE),
        Median = ~median(., na.rm = TRUE),
        Mean   = ~mean(., na.rm = TRUE),
        Q3     = ~quantile(., 0.75, na.rm = TRUE),
        Max    = ~max(., na.rm = TRUE),
        SD     = ~sd(., na.rm = TRUE)
      ),
      .names = "{col}_{fn}"
    ),
    Total_Students = n()
  )

correlation <- cor(imputed_variables[, c("ESCS", "MATHH", "READD", "SCIEE")])

#Saving the changes
saveRDS(imputed_variables, "data/imputed_variables.rds")
print(correlation)
