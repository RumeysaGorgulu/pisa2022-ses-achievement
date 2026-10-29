# 01 — Data preparation and exploratory analysis
# PISA 2022: socioeconomic background and achievement in math, reading, science
#
# Input : data/CY08MSP_STU_QQQ.SAV  (OECD PISA 2022 Student Questionnaire, SPSS)
# Output: data/analysis_data.rds      (cleaned student-level data, git-ignored)
#         results/item_labels.csv     (SES survey items and their wording)
#         results/country_summary.csv (weighted country means, all 10 plausible values)
#         results/data_prep_log.csv   (sample sizes after each step)
#         plots/missing_per_student.png, plots/retention_threshold.png
#
# Run from the repository root.

suppressPackageStartupMessages({
  library(haven)
  library(tidyverse)
})

dir.create("plots",   showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

# 1. Load data ---------------------------------------------------------------
# The SPSS file is ~2 GB; it is converted to RDS once for faster reloading.

raw_path <- "data/CY08MSP_STU_QQQ.SAV"
rds_path <- "data/pisa2022sq.rds"

if (file.exists(rds_path)) {
  pisa <- readRDS(rds_path)
} else {
  message("Reading SPSS file (this can take several minutes)...")
  pisa <- read_sav(raw_path)
  saveRDS(pisa, rds_path)
}

# 2. Select variables ---------------------------------------------------------
# - 10 plausible values (PVs) per subject are kept separately. PVs are random
#   draws from each student's proficiency distribution; analyses are run once
#   per PV and the results combined, rather than averaging PVs per student
#   (averaging understates variance and biases R² upward).
# - W_FSTUWT is the final student weight (used for descriptive statistics).
# - SES items: home possessions, books, parental education/occupation.

ses_pattern <- "^ST(250|251|253|254|255|256|005|006|007|008|258|259)Q.*"
question_columns <- str_subset(colnames(pisa), ses_pattern)

pv_cols <- c(paste0("PV", 1:10, "MATH"),
             paste0("PV", 1:10, "READ"),
             paste0("PV", 1:10, "SCIE"))

item_labels <- tibble(
  item  = question_columns,
  label = map_chr(question_columns, ~ attr(pisa[[.x]], "label") %||% NA_character_)
)
write_csv(item_labels, "results/item_labels.csv")

variables <- pisa %>%
  select(CNT, CNTRYID, CNTSTUID, W_FSTUWT, ESCS,
         all_of(pv_cols), all_of(question_columns)) %>%
  zap_labels() %>%
  mutate(CNT = as.character(CNT))

rm(pisa); invisible(gc())

prep_log <- tibble(step = "All students", n = nrow(variables),
                   countries = n_distinct(variables$CNT))

# 3. Clean --------------------------------------------------------------------
# Costa Rica has no ESCS values at all, so it is excluded.
variables <- variables %>% filter(CNT != "CRI")

# Remaining missing ESCS: country-mean imputation (ESCS is used only for
# descriptive statistics and as a single-predictor baseline).
escs_missing_pct <- mean(is.na(variables$ESCS)) * 100
variables <- variables %>%
  group_by(CNT) %>%
  mutate(ESCS = if_else(is.na(ESCS), mean(ESCS, na.rm = TRUE), ESCS)) %>%
  ungroup()

# ST254 and ST256 code 5 = "I don't know"; recoded to 0 (treated as absent).
variables <- variables %>%
  mutate(across(matches("^ST(254|256)Q"), ~ if_else(. == 5, 0, .)))

prep_log <- add_row(prep_log, step = "Excluding Costa Rica (no ESCS)",
                    n = nrow(variables), countries = n_distinct(variables$CNT))

# 4. Missing survey items -----------------------------------------------------
# Students missing more than 14 SES items are excluded; remaining item-level
# gaps are filled with the country mean of that item.

variables$NA_count <- rowSums(is.na(variables[question_columns]))

p_na <- ggplot(variables, aes(x = NA_count)) +
  geom_histogram(binwidth = 1, fill = "steelblue", color = "white") +
  labs(title = "Missing SES items per student",
       x = "Number of missing items", y = "Students") +
  theme_minimal()
ggsave("plots/missing_per_student.png", p_na, width = 7, height = 4, dpi = 150)

retention <- tibble(
  threshold = 0:length(question_columns),
  retained_pct = map_dbl(threshold, ~ mean(variables$NA_count <= .x) * 100)
)

threshold <- 14
p_ret <- ggplot(retention, aes(threshold, retained_pct)) +
  geom_line() + geom_point(size = 1) +
  geom_vline(xintercept = threshold, linetype = "dashed", color = "red") +
  labs(title = "Share of students retained by missing-item threshold",
       x = "Maximum missing items allowed", y = "Students retained (%)") +
  theme_minimal()
ggsave("plots/retention_threshold.png", p_ret, width = 7, height = 4, dpi = 150)

analysis_data <- variables %>%
  filter(NA_count <= threshold) %>%
  select(-NA_count) %>%
  group_by(CNT) %>%
  mutate(across(all_of(question_columns),
                ~ coalesce(., mean(., na.rm = TRUE), 0))) %>%
  ungroup()

stopifnot(sum(is.na(analysis_data[c("ESCS", question_columns)])) == 0)

prep_log <- add_row(prep_log,
                    step = paste0("Excluding students missing > ", threshold, " items"),
                    n = nrow(analysis_data), countries = n_distinct(analysis_data$CNT))
prep_log$escs_imputed_pct <- c(NA, round(escs_missing_pct, 2), NA)
write_csv(prep_log, "results/data_prep_log.csv")
print(prep_log)

saveRDS(analysis_data, "data/analysis_data.rds")

# 5. Exploratory analysis -----------------------------------------------------
# Country statistics are weighted (W_FSTUWT). For scores, each statistic is
# computed separately for each of the 10 PVs and then averaged.

w_mean <- function(x, w) sum(w * x) / sum(w)
w_sd   <- function(x, w) sqrt(sum(w * (x - w_mean(x, w))^2) / sum(w))

pv_stat <- function(df, subject, fun) {
  mean(map_dbl(1:10, ~ fun(df[[paste0("PV", .x, subject)]], df$W_FSTUWT)))
}

country_summary <- analysis_data %>%
  group_by(CNT) %>%
  group_modify(~ tibble(
    n         = nrow(.x),
    escs_mean = w_mean(.x$ESCS, .x$W_FSTUWT),
    escs_sd   = w_sd(.x$ESCS, .x$W_FSTUWT),
    math_mean = pv_stat(.x, "MATH", w_mean),
    math_sd   = pv_stat(.x, "MATH", w_sd),
    read_mean = pv_stat(.x, "READ", w_mean),
    read_sd   = pv_stat(.x, "READ", w_sd),
    scie_mean = pv_stat(.x, "SCIE", w_mean),
    scie_sd   = pv_stat(.x, "SCIE", w_sd)
  )) %>%
  ungroup() %>%
  mutate(across(where(is.double), ~ round(., 2)))

write_csv(country_summary, "results/country_summary.csv")

# Weighted correlation of ESCS with each subject, averaged over PVs
escs_cor <- map_dfr(c(MATH = "MATH", READ = "READ", SCIE = "SCIE"), function(s) {
  r <- map_dbl(1:10, function(i) {
    cov.wt(analysis_data[c("ESCS", paste0("PV", i, s))],
           wt = analysis_data$W_FSTUWT / sum(analysis_data$W_FSTUWT),
           cor = TRUE)$cor[1, 2]
  })
  tibble(subject = s, r_escs = round(mean(r), 3))
})
write_csv(escs_cor, "results/escs_correlations.csv")
print(escs_cor)
