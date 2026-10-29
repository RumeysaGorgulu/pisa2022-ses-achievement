# 02 — Visualization
# ESCS distribution by country and world maps of weighted country mean scores.
#
# Requires: data/analysis_data.rds and results/country_summary.csv (from 01).
# Run from the repository root.

suppressPackageStartupMessages({
  library(tidyverse)
  library(countrycode)
  library(maps)
  library(plotly)
  library(htmlwidgets)
})

dir.create("plots", showWarnings = FALSE)

analysis_data   <- readRDS("data/analysis_data.rds")
country_summary <- read_csv("results/country_summary.csv", show_col_types = FALSE)

# 1. ESCS by country (ordered by median) -------------------------------------

escs_plot <- analysis_data %>%
  mutate(CNT = fct_reorder(CNT, ESCS, .fun = median)) %>%
  ggplot(aes(x = CNT, y = ESCS)) +
  geom_boxplot(outlier.size = 0.1, outlier.alpha = 0.2,
               fill = "grey85", color = "grey30") +
  coord_flip() +
  labs(title = "Distribution of ESCS by country, PISA 2022",
       subtitle = "Countries ordered by median ESCS",
       x = NULL, y = "ESCS (index of economic, social and cultural status)") +
  theme_minimal(base_size = 10)

ggsave("plots/escs_boxplot.png", escs_plot, width = 8, height = 12, dpi = 150)

tryCatch(
  saveWidget(ggplotly(escs_plot), "plots/escs_boxplot_interactive.html"),
  error = function(e) message("Skipped interactive boxplot: ", conditionMessage(e))
)

# 2. World maps of country means ---------------------------------------------
# Country means are weighted and averaged over the 10 plausible values
# (computed in 01). Map regions are matched to PISA country codes via ISO3.
# PISA codes that are not ISO3: TAP = Chinese Taipei, KSV = Kosovo,
# QAZ = Baku (Azerbaijan), QUR = Ukrainian regions. Baku and the Ukrainian
# regions are drawn at national level and should be read with that caveat.

world_map <- map_data("world") %>%
  filter(region != "Antarctica") %>%
  mutate(CNT = countrycode(region, origin = "country.name", destination = "iso3c",
                           custom_match = c(Taiwan = "TAP", Kosovo = "KSV",
                                            Azerbaijan = "QAZ", Ukraine = "QUR"),
                           warn = FALSE))

unmatched <- setdiff(country_summary$CNT, world_map$CNT)
if (length(unmatched)) {
  message("PISA participants not drawn on the map (no matching polygon): ",
          paste(unmatched, collapse = ", "))
}

plot_map <- function(score_column, subject) {
  map_df <- world_map %>%
    left_join(country_summary %>% select(CNT, score = all_of(score_column)),
              by = "CNT")

  ggplot(map_df, aes(long, lat, group = group, fill = score,
                     text = paste0(region, ": ", round(score)))) +
    geom_polygon(color = "white", linewidth = 0.1) +
    scale_fill_viridis_c(option = "viridis", na.value = "grey85",
                         name = "Mean score") +
    coord_quickmap() +
    labs(title = paste("PISA 2022 mean", tolower(subject), "score by country"),
         subtitle = "Weighted means over 10 plausible values; grey = did not participate",
         caption = "Baku (Azerbaijan) and Ukrainian regions shown at national level.") +
    theme_void() +
    theme(legend.position = "right")
}

subjects <- c(math_mean = "Math", read_mean = "Reading", scie_mean = "Science")

for (col in names(subjects)) {
  subject <- subjects[[col]]
  p <- plot_map(col, subject)
  ggsave(paste0("plots/map_", tolower(subject), ".png"), p,
         width = 10, height = 5.5, dpi = 150, bg = "white")
  tryCatch(
    saveWidget(ggplotly(p, tooltip = "text"),
               paste0("plots/map_", tolower(subject), "_interactive.html")),
    error = function(e) message("Skipped interactive map: ", conditionMessage(e))
  )
}

# 3. ESCS vs mean math score (country level) ---------------------------------

p_scatter <- ggplot(country_summary, aes(escs_mean, math_mean)) +
  geom_smooth(method = "lm", formula = y ~ x, color = "grey50", se = FALSE,
              linewidth = 0.6) +
  geom_point(color = "steelblue", size = 2) +
  geom_text(aes(label = CNT), size = 2.3, vjust = -0.8, color = "grey30") +
  labs(title = "Country mean ESCS vs. mean math score, PISA 2022",
       x = "Mean ESCS", y = "Mean math score") +
  theme_minimal()

ggsave("plots/escs_vs_math_country.png", p_scatter, width = 8, height = 6, dpi = 150)
