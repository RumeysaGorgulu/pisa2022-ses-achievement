# PISA 2022 — Predictive Modeling (LASSO + KNN)
# Socio-Economic Disparities in Math, Reading, and Science Skills

# Uses LASSO regression for SES variable selection and KNN regression for
# outcome prediction across math, reading, and science scores.

# NOTE: Requires data/imputed_variables.rds produced by R/01_data_prep_eda.R.
# Run all scripts from the repository root.

library(glmnet)
library(kknn)
library(tidymodels)
library(tidyverse)

dir.create("plots", showWarnings = FALSE)

# Load preprocessed data
imputed_variables <- readRDS("data/imputed_variables.rds")

question_columns <- colnames(imputed_variables) %>%
  str_subset("^ST(250|251|253|254|255|256|005|006|007|008|258|259)Q.*")

# 1. LASSO Regression
# LASSO identifies the most important SES predictors for each subject by
# shrinking less important coefficients to zero via cross-validated lambda.

predictors <- imputed_variables %>%
  select(all_of(question_columns))

run_lasso <- function(target_variable) {
  Y <- imputed_variables[[target_variable]]
  X <- as.matrix(predictors)

  lasso_model <- cv.glmnet(X, Y, alpha = 1)
  best_lambda <- lasso_model$lambda.min

  coef_matrix <- coef(lasso_model, s = best_lambda)
  coeff <- data.frame(
    Feature     = rownames(coef_matrix),
    Coefficient = coef_matrix[, 1]
  )
  coeff <- coeff[coeff$Coefficient != 0, ]
  coeff <- coeff[order(abs(coeff$Coefficient), decreasing = TRUE), ]

  print(paste("Best lambda for", target_variable, ":", best_lambda))
  print(paste("Top 10 features for", target_variable))
  print(head(coeff, 10))

  plot(lasso_model)

  return(list(
    model        = lasso_model,
    best_lambda  = best_lambda,
    coefficients = coeff
  ))
}

mathh_results <- run_lasso("MATHH")
readd_results <- run_lasso("READD")
sciee_results <- run_lasso("SCIEE")

# Save LASSO cross-validation plots
png("plots/lasso_math.png"); plot(mathh_results$model); dev.off()
png("plots/lasso_reading.png"); plot(readd_results$model); dev.off()
png("plots/lasso_science.png"); plot(sciee_results$model); dev.off()

# 2. KNN Regression (U.S. data only due to computational constraints)
# Predicts math, reading, and science scores using 10-fold cross-validation
# to tune the number of neighbors. Evaluated with RMSE, R², and MAE.

usa_data <- imputed_variables %>% filter(CNT == "USA")

set.seed(100)
split      <- initial_split(usa_data, prop = 0.8, strata = MATHH)
train_data <- training(split)
test_data  <- testing(split)

knn_spec <- nearest_neighbor(neighbors = tune()) %>%
  set_engine("kknn") %>%
  set_mode("regression")

cv_folds     <- vfold_cv(train_data, v = 10)
knn_workflow <- workflow() %>% add_model(knn_spec)
grid         <- expand.grid(neighbors = c(1, 3, 5, 10, 20))

tune_and_interpret <- function(outcome_var) {
  knn_recipe <- recipe(as.formula(paste(outcome_var, "~ .")), data = train_data) %>%
    step_zv(all_predictors()) %>%
    step_normalize(all_numeric_predictors()) %>%
    step_novel(all_nominal_predictors())

  wf <- knn_workflow %>% add_recipe(knn_recipe)

  tune_results <- tune_grid(
    wf,
    resamples = cv_folds,
    grid      = grid,
    metrics   = metric_set(rmse, rsq)
  )

  best_params    <- select_best(tune_results, metric = "rmse")
  final_workflow <- finalize_workflow(wf, best_params)
  final_fit      <- final_workflow %>% fit(data = train_data)

  predictions <- predict(final_fit, new_data = test_data) %>%
    bind_cols(test_data) %>%
    mutate(residual = !!sym(outcome_var) - .pred)

  metrics <- predictions %>%
    metrics(truth = !!sym(outcome_var), estimate = .pred)

  residual_plot <- ggplot(predictions, aes(x = .pred, y = residual)) +
    geom_point(alpha = 0.5) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    labs(title = paste("Residual Plot for", outcome_var),
         x = "Predicted Values", y = "Residuals") +
    theme_minimal()

  print(metrics)
  print(residual_plot)

  list(
    final_fit     = final_fit,
    predictions   = predictions,
    metrics       = metrics,
    residual_plot = residual_plot,
    best_params   = best_params
  )
}

math_results    <- tune_and_interpret("MATHH")
reading_results <- tune_and_interpret("READD")
science_results <- tune_and_interpret("SCIEE")

# Save residual plots
ggsave("plots/residual_math.png", math_results$residual_plot, width = 8, height = 5)
ggsave("plots/residual_reading.png", reading_results$residual_plot, width = 8, height = 5)
ggsave("plots/residual_science.png", science_results$residual_plot, width = 8, height = 5)
