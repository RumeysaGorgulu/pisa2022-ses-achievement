# PISA 2022 — Data Visualization
# Socio-Economic Disparities in Math, Reading, and Science Skills

# Visualizes ESCS scores and academic performance across 79 countries using
# boxplots, interactive plotly charts, and world maps.
#
# NOTE: Requires data/imputed_variables.rds produced by R/01_data_prep_eda.R.
# Run all scripts from the repository root.

library(tidyverse)
library(ggplot2)
library(plotly)
library(countrycode)
library(htmlwidgets)

dir.create("plots", showWarnings = FALSE)

# Load preprocessed data
imputed_variables <- readRDS("data/imputed_variables.rds")

# 1. ESCS Scores by Country (Boxplot)

# Static boxplot
escs_plot <- ggplot(imputed_variables, aes(x = CNT, y = ESCS, fill = CNT)) +
  geom_boxplot(outlier.size = .01, outlier.colour = "black") +
  labs(title = "ESCS Scores by Country", x = "Country", y = "ESCS Scores") +
  theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
  guides(fill = "none")

print(escs_plot)
ggsave("plots/escs_boxplot.png", escs_plot, width = 12, height = 6)

# Interactive version
saveWidget(ggplotly(escs_plot), "plots/escs_boxplot_interactive.html")

# 2. World Maps of Academic Scores
# Country codes matched to country names; unmatched codes manually assigned.

world_map <- map_data("world")

imputed_variables <- imputed_variables %>%
  mutate(COUNTRY_NAME = countrycode(CNTRYID, origin = "un", destination = "country.name",
                                    warn = FALSE)) %>%
  mutate(
    COUNTRY_NAME = case_when(
      CNTRYID == 158 ~ "Taiwan",
      CNTRYID == 383 ~ "Kosovo",
      CNTRYID == 826 ~ "UK",
      CNTRYID == 840 ~ "USA",
      CNTRYID == 901 ~ "Special Region or Entity",
      TRUE ~ countrycode(CNTRYID, origin = "un", destination = "country.name", warn = FALSE)
    )
  )

plot_map <- function(world_map, score_column, name) {
  world_map <- world_map %>%
    group_by(region) %>%
    mutate(score = score_column[match(region, imputed_variables$COUNTRY_NAME)])

  ggplot(data = world_map) +
    geom_polygon(aes(x = long, y = lat, group = group, fill = score),
                 color = "black", linewidth = 0.1) +
    scale_fill_viridis_c(option = "viridis", na.value = "grey60") +
    labs(title = paste("World Map of", name, "Scores"))
}

map_M <- plot_map(world_map, imputed_variables$MATHH, "Math")
map_R <- plot_map(world_map, imputed_variables$READD, "Reading")
map_S <- plot_map(world_map, imputed_variables$SCIEE, "Science")

# Static maps
print(map_M)
print(map_R)
print(map_S)

ggsave("plots/map_math.png", map_M, width = 10, height = 6)
ggsave("plots/map_reading.png", map_R, width = 10, height = 6)
ggsave("plots/map_science.png", map_S, width = 10, height = 6)

# Interactive maps
saveWidget(ggplotly(map_M), "plots/map_math_interactive.html")
saveWidget(ggplotly(map_R), "plots/map_reading_interactive.html")
saveWidget(ggplotly(map_S), "plots/map_science_interactive.html")
