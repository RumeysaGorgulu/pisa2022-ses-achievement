# 03 — Predictive modeling: how much of achievement do SES survey items predict?
#
# Design (U.S. sample; one fixed 80/20 train/test split):
#   For each subject (math, reading, science) and each plausible value PV1–PV10:
#     1. LASSO on the training set selects SES items (lambda.1se, 10-fold CV).
#     2. Three models are fit on the training set and scored on the test set:
#          - OLS on ESCS only            (single-index baseline)
#          - OLS on LASSO-selected items (linear model)
#          - KNN on LASSO-selected items (non-linear model, k tuned by 10-fold CV)
#   Metrics (RMSE, MAE, R²) are averaged across the 10 PVs; the min–max range
#   across PVs is also reported.
#
# Predictors are SES survey items only. Other subjects' scores, IDs and weights
# are never used as predictors.
#
# Requires: data/analysis_data.rds (from 01). Run from the repository root.
# Runtime: about 10–20 minutes. For a quick check set N_PV <- 1.

suppressPackageStartupMessages({
  library(tidyverse)
  library(glmnet)
  library(tidymodels)
  library(kknn)
})

N_PV   <- 10
K_GRID <- tibble(neighbors = c(5, 10, 20, 40, 80))

dir.create("plots",   showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

analysis_data <- readRDS("data/analysis_data.rds")
item_labels   <- read_csv("results/item_labels.csv", show_col_types = FALSE)
items <- item_labels$item

usa <- analysis_data %>% filter(CNT == "USA")

set.seed(100)
split <- initial_split(usa, prop = 0.8, strata = PV1MATH)
train <- training(split)
test  <- testing(split)

folds  <- vfold_cv(train, v = 10)
foldid <- sample(rep(1:10, length.out = nrow(train)))  # same folds for every LASSO

# Drop items with no variance in the U.S. training data
items <- items[map_lgl(items, ~ sd(train[[.x]]) > 0)]
X_train <- as.matrix(train[items])

eval_metrics <- metric_set(rmse, mae, rsq_trad)  # rsq_trad = 1 - SSE/SST

score <- function(truth, estimate) {
  eval_metrics(tibble(truth = truth, estimate = estimate),
               truth = truth, estimate = estimate) %>%
    select(metric = .metric, value = .estimate)
}

subjects <- c(MATH = "Math", READ = "Reading", SCIE = "Science")

metrics_all   <- list()
selection_all <- list()
best_k_all    <- list()

for (subj in names(subjects)) {
  for (pv in seq_len(N_PV)) {
    y <- paste0("PV", pv, subj)
    message(sprintf("%s, PV%d", subjects[[subj]], pv))

    # 1. LASSO selection 
    cv_fit <- cv.glmnet(X_train, train[[y]], alpha = 1, foldid = foldid)
    b <- coef(cv_fit, s = "lambda.1se")[-1, 1]
    selected <- names(b)[b != 0]
    if (length(selected) == 0) selected <- items

    selection_all[[length(selection_all) + 1]] <-
      tibble(subject = subj, pv = pv, item = names(b), coef = unname(b))

    if (pv == 1) {
      png(paste0("plots/lasso_cv_", tolower(subjects[[subj]]), ".png"),
          width = 1200, height = 900, res = 150)
      plot(cv_fit)
      title(paste("LASSO cross-validation:", subjects[[subj]], "(PV1)"), line = 2.5)
      dev.off()
    }

    # 2a. OLS, ESCS only 
    m_escs <- lm(reformulate("ESCS", y), data = train)

    # 2b. OLS, selected items 
    m_ols <- lm(reformulate(selected, y), data = train)

    # 2c. KNN, selected items 
    rec <- recipe(reformulate(selected, y), data = train[c(y, selected)]) %>%
      step_normalize(all_predictors())
    wf <- workflow() %>%
      add_recipe(rec) %>%
      add_model(nearest_neighbor(neighbors = tune()) %>%
                  set_engine("kknn") %>% set_mode("regression"))
    tuned  <- tune_grid(wf, resamples = folds, grid = K_GRID,
                        metrics = metric_set(rmse))
    best   <- select_best(tuned, metric = "rmse")
    m_knn  <- fit(finalize_workflow(wf, best), data = train)
    best_k_all[[length(best_k_all) + 1]] <-
      tibble(subject = subj, pv = pv, best_k = best$neighbors)

    # 3. Test-set evaluation 
    preds <- list(
      "OLS: ESCS only"      = predict(m_escs, test),
      "OLS: selected items" = predict(m_ols, test),
      "KNN: selected items" = predict(m_knn, test)$.pred
    )

    metrics_all[[length(metrics_all) + 1]] <- imap_dfr(preds, function(p, model) {
      score(test[[y]], p) %>%
        mutate(subject = subj, pv = pv, model = model, n_items = length(selected))
    })

    if (pv == 1) {
      res_df <- tibble(predicted = preds[["KNN: selected items"]],
                       residual  = test[[y]] - preds[["KNN: selected items"]])
      p_res <- ggplot(res_df, aes(predicted, residual)) +
        geom_point(alpha = 0.3, size = 0.8) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
        geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                    color = "steelblue", linewidth = 0.7) +
        labs(title = paste("KNN residuals on test set:", subjects[[subj]], "(PV1)"),
             x = "Predicted score", y = "Residual") +
        theme_minimal()
      ggsave(paste0("plots/residual_", tolower(subjects[[subj]]), ".png"),
             p_res, width = 7, height = 4.5, dpi = 150)
    }
  }
}

# 4. Combine across plausible values 

metrics_by_pv <- bind_rows(metrics_all)
write_csv(metrics_by_pv, "results/metrics_by_pv.csv")

metrics_summary <- metrics_by_pv %>%
  group_by(subject, model, metric) %>%
  summarise(mean = mean(value), min = min(value), max = max(value),
            .groups = "drop") %>%
  mutate(subject = subjects[subject])
write_csv(metrics_summary, "results/metrics_summary.csv")

best_k <- bind_rows(best_k_all)
write_csv(best_k, "results/knn_best_k.csv")

selection <- bind_rows(selection_all) %>%
  group_by(subject, item) %>%
  summarise(selected_pct = mean(coef != 0) * 100,
            mean_coef    = mean(coef), .groups = "drop") %>%
  left_join(item_labels, by = "item") %>%
  mutate(subject = subjects[subject]) %>%
  arrange(subject, desc(abs(mean_coef)))
write_csv(selection, "results/lasso_selection.csv")

# 5. Figures for the README

model_levels <- c("OLS: ESCS only", "OLS: selected items", "KNN: selected items")

p_r2 <- metrics_summary %>%
  filter(metric == "rsq_trad") %>%
  mutate(model = factor(model, levels = model_levels)) %>%
  ggplot(aes(subject, mean, fill = model)) +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_errorbar(aes(ymin = min, ymax = max),
                position = position_dodge(0.8), width = 0.2) +
  scale_fill_manual(values = c("grey70", "steelblue", "darkorange")) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Test-set R-squared of SES-based models (U.S., PISA 2022)",
       subtitle = "Bars: mean over plausible values; whiskers: min to max",
       x = NULL, y = "R-squared (test set)", fill = NULL) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave("plots/model_comparison_r2.png", p_r2, width = 7.5, height = 4.5, dpi = 150)

top_math <- selection %>%
  filter(subject == "Math", mean_coef != 0) %>%
  slice_max(abs(mean_coef), n = 15, with_ties = FALSE) %>%
  mutate(label = coalesce(str_trunc(label, 60), item),
         label = fct_reorder(paste0(item, ": ", label), mean_coef))

p_coef <- ggplot(top_math, aes(mean_coef, label, fill = mean_coef > 0)) +
  geom_col() +
  scale_fill_manual(values = c("TRUE" = "steelblue", "FALSE" = "firebrick"),
                    guide = "none") +
  labs(title = "Largest LASSO coefficients for math (U.S.)",
       subtitle = "Mean coefficient across plausible values (score points per item unit)",
       x = "Coefficient", y = NULL) +
  theme_minimal(base_size = 9)
ggsave("plots/lasso_top_items_math.png", p_coef, width = 9, height = 5.5, dpi = 150)

# 6. Markdown table to paste into README.md 
fmt <- function(m, lo, hi, digits) {
  sprintf(paste0("%.", digits, "f (%.", digits, "f–%.", digits, "f)"), m, lo, hi)
}

table_md <- metrics_summary %>%
  mutate(cell = if_else(metric == "rsq_trad", fmt(mean, min, max, 3),
                        fmt(mean, min, max, 1)),
         metric = recode(metric, rmse = "RMSE", mae = "MAE", rsq_trad = "R²"),
         model = factor(model, levels = model_levels)) %>%
  select(subject, model, metric, cell) %>%
  pivot_wider(names_from = metric, values_from = cell) %>%
  arrange(subject, model) %>%
  select(Subject = subject, Model = model, `R²`, RMSE, MAE)

md_lines <- c(
  "| Subject | Model | R² | RMSE | MAE |",
  "|---|---|---|---|---|",
  pmap_chr(table_md, function(Subject, Model, `R²`, RMSE, MAE)
    paste0("| ", Subject, " | ", Model, " | ", `R²`, " | ", RMSE, " | ", MAE, " |"))
)
writeLines(md_lines, "results/results_table.md")
cat(md_lines, sep = "\n")

writeLines(capture.output(sessionInfo()), "results/sessionInfo.txt")
message("Done. Paste results/results_table.md into README.md.")
