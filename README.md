# Predicting Student Achievement from Socioeconomic Status: LASSO + KNN on PISA 2022

Machine learning pipeline in R that predicts 15-year-olds' math, reading, and science scores from home and family background variables in the OECD PISA 2022 dataset (79 countries, N ≈ 614,000 students).

**Task:** Given ~40 socioeconomic survey items, (1) select the features that matter and (2) predict a student's test scores.

**Approach:** LASSO regression for feature selection → KNN regression for prediction, with 10-fold cross-validation and held-out test evaluation.

## Results

| Subject | RMSE | R² | MAE |
|---------|------|----|-----|
| Math | 52.6 | **0.689** | 42.2 |
| Reading | 63.5 | **0.676** | 50.2 |
| Science | 58.5 | **0.717** | 47.0 |

Socioeconomic indicators alone explain roughly 70% of score variance (U.S. test set; PISA scores have SD ≈ 100).

**Feature selection:** LASSO retained parental doctoral education as the strongest positive predictor in all three subjects; digital device ownership had a consistent negative coefficient.

| LASSO cross-validation (math) | KNN residuals (math) |
|---|---|
| ![LASSO math](plots/lasso_math.png) | ![Residual math](plots/residual_math.png) |

## Pipeline

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `R/01_data_prep_eda.R` | Converts the 1.95 GB SPSS file to RDS, filters variables by missingness, imputes ESCS at the country level, computes summary statistics and correlations |
| 2 | `R/02_visualization.R` | ESCS distribution by country; world maps of mean scores; interactive Plotly versions ([live demo](https://rpubs.com/RumeysaGorgulu/pisa2022-visualization)) |
| 3 | `R/03_modeling.R` | LASSO (`glmnet`, λ by 10-fold CV MSE) per subject → KNN regression (`tidymodels` + `kknn`, k tuned by 10-fold CV) → RMSE / R² / MAE on held-out test set + residual plots |

## Methods

- **Preprocessing:** threshold-based removal of high-missingness variables; country-level mean imputation of the ESCS index.
- **Feature selection:** L1-regularized regression; λ chosen at minimum cross-validated MSE, run separately for math, reading, and science.
- **Prediction:** KNN regression on LASSO-selected features; k tuned via 10-fold CV; train/test split on U.S. sample.
- **Evaluation:** RMSE, R², MAE; residual-vs-fitted plots to check for systematic error.

## Exploratory figures

| ESCS by country | Mean math score by country |
|---|---|
| ![ESCS boxplot](plots/escs_boxplot.png) | ![Math map](plots/map_math.png) |

Reading and science versions of every plot are in `plots/`.

## Reproducing

1. Download the PISA 2022 Student Questionnaire (SPSS) from https://www.oecd.org/pisa/data/ and place `CY08MSP_STU_QQQ.SAV` in `data/`.
2. Install dependencies:
   ```r
   install.packages(c("haven", "tidyverse", "stringr", "ggplot2", "plotly",
                      "countrycode", "htmlwidgets", "glmnet", "tidymodels", "kknn"))
   ```
3. From the repository root, run `R/01_data_prep_eda.R` → `R/02_visualization.R` → `R/03_modeling.R`.

Intermediate data are written to `data/` (git-ignored); figures to `plots/`.

## License

MIT — see `LICENSE`.

## Author

Rumeysa Gorgulu
