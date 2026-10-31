# 04 — Showcase figures for the README
# Polished static figures and an interactive world map, built only from the
# result files written by steps 01–03 (no raw data needed).
#
# Requires: results/country_summary.csv, results/lasso_selection.csv,
#           results/metrics_summary.csv
# Writes:   plots/showcase_*.png and docs/index.html (interactive map)
# Run from the repository root, after 01–03.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(maps)
  library(plotly)
  library(htmlwidgets)
})

dir.create("plots", showWarnings = FALSE)
dir.create("docs", showWarnings = FALSE)

country <- read_csv("results/country_summary.csv", show_col_types = FALSE)
lasso   <- read_csv("results/lasso_selection.csv", show_col_types = FALSE)
metrics <- read_csv("results/metrics_summary.csv", show_col_types = FALSE)

NAVY <- "#1b3a6b"; ORANGE <- "#e8862a"; GREY <- "#a9b1bd"; INK <- "#1f2a3a"

theme_showcase <- function(base = 15) {
  theme_minimal(base_size = base) +
    theme(plot.title = element_text(face = "bold", size = base + 5, color = INK),
          plot.subtitle = element_text(size = base, color = "grey35",
                                       margin = margin(b = 10)),
          plot.caption = element_text(size = base - 4, color = "grey45"),
          panel.grid.minor = element_blank(),
          plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(14, 18, 10, 14),
          plot.title.position = "plot", plot.caption.position = "plot")
}

# ---------------------------------------------------------------------------
# Country codes and names
# PISA codes that are not standard ISO3: TAP = Chinese Taipei, KSV = Kosovo,
# QAZ = Baku (Azerbaijan), QUR = Ukrainian regions.
# ---------------------------------------------------------------------------
pisa_to_iso <- c(TAP = "TWN", KSV = "XKX", QAZ = "AZE", QUR = "UKR")
country <- country %>%
  mutate(iso3 = coalesce(unname(pisa_to_iso[CNT]), CNT))

iso <- maps::iso3166 %>%
  distinct(a3, .keep_all = TRUE) %>%
  transmute(iso3 = a3, region = str_remove(mapname, "\\(.*$"),
            name = ISOname)
name_fix <- c(XKX = "Kosovo", TWN = "Chinese Taipei", AZE = "Baku (Azerbaijan)",
              UKR = "Ukrainian regions")
country <- country %>%
  left_join(iso %>% select(iso3, name), by = "iso3") %>%
  mutate(name = coalesce(unname(name_fix[iso3]), name, CNT))

# ---------------------------------------------------------------------------
# 1. Static world maps (one per subject)
# ---------------------------------------------------------------------------
world <- map_data("world") %>%
  filter(region != "Antarctica") %>%
  left_join(iso %>% select(region, iso3) %>% distinct(region, .keep_all = TRUE),
            by = "region") %>%
  mutate(iso3 = case_when(region == "Kosovo" ~ "XKX",
                          region == "Taiwan" ~ "TWN",
                          TRUE ~ iso3))

subjects <- c(math_mean = "Math", read_mean = "Reading", scie_mean = "Science")

for (col in names(subjects)) {
  subject <- subjects[[col]]
  df <- world %>% left_join(country %>% select(iso3, score = all_of(col)), by = "iso3")
  p <- ggplot(df, aes(long, lat, group = group, fill = score)) +
    geom_polygon(color = "white", linewidth = 0.12) +
    scale_fill_viridis_c(option = "viridis", na.value = "#e4e7ec",
                         name = paste("Mean", tolower(subject), "score"),
                         guide = guide_colorbar(barwidth = unit(14, "cm"),
                                                barheight = unit(0.45, "cm"),
                                                title.position = "top",
                                                title.hjust = 0.5)) +
    coord_quickmap(xlim = c(-170, 190), ylim = c(-56, 84), expand = FALSE) +
    labs(title = paste("PISA 2022:", subject, "performance around the world"),
         subtitle = "Weighted country means over 10 plausible values  |   grey = did not participate",
         caption = "Baku (Azerbaijan) and the Ukrainian regions are shown at national level.") +
    theme_showcase() +
    theme(axis.text = element_blank(), axis.title = element_blank(),
          panel.grid = element_blank(), legend.position = "bottom")
  ggsave(paste0("plots/showcase_map_", tolower(subject), ".png"), p,
         width = 12, height = 7, dpi = 150)
}

# ---------------------------------------------------------------------------
# 2. Interactive map (GitHub Pages: docs/index.html)
# ---------------------------------------------------------------------------
hover <- function(score, label) {
  paste0("<b>", country$name, "</b><br>", label, ": ", round(score),
         "<br>Mean ESCS: ", sprintf("%.2f", country$escs_mean),
         "<br>Students: ", format(country$n, big.mark = ","))
}
geo <- list(projection = list(type = "natural earth"), showframe = FALSE,
            showcoastlines = FALSE, showland = TRUE, landcolor = "#e4e7ec",
            showcountries = TRUE, countrycolor = "white", bgcolor = "rgba(0,0,0,0)")
fig <- plot_ly()
for (i in seq_along(subjects)) {
  col <- names(subjects)[i]; lab <- paste("Mean", tolower(subjects[[i]]), "score")
  fig <- fig %>% add_trace(
    type = "choropleth", locations = country$iso3, z = country[[col]],
    text = hover(country[[col]], lab), hoverinfo = "text",
    colorscale = "Viridis", zmin = 330, zmax = 580, visible = i == 1,
    marker = list(line = list(color = "white", width = 0.4)),
    colorbar = list(title = list(text = "Mean score"), len = 0.6),
    name = subjects[[i]])
}
buttons <- lapply(seq_along(subjects), function(i) list(
  method = "update", label = subjects[[i]],
  args = list(list(visible = seq_along(subjects) == i),
              list(title = list(text = paste0("<b>PISA 2022: ", subjects[[i]],
                                              " performance around the world</b>"))))))
fig <- fig %>% layout(
  title = list(text = "<b>PISA 2022: Math performance around the world</b>", x = 0.02),
  geo = geo, margin = list(l = 0, r = 0, t = 70, b = 0),
  font = list(family = "Segoe UI, Helvetica, Arial, sans-serif"),
  updatemenus = list(list(type = "buttons", direction = "right", x = 0.02, y = 1.0,
                          xanchor = "left", yanchor = "top", buttons = buttons,
                          showactive = TRUE)),
  annotations = list(list(text = "Hover over a country for details. Weighted means over 10 plausible values.",
                          x = 0.02, y = -0.02, xref = "paper", yref = "paper",
                          showarrow = FALSE, font = list(size = 12, color = "grey"))))
fig <- config(fig, displaylogo = FALSE)
saveWidget(fig, "docs/index.html", selfcontained = TRUE,
           title = "PISA 2022 world map")
unlink("docs/index_files", recursive = TRUE)

# ---------------------------------------------------------------------------
# 3. What LASSO kept: top items for math, with readable labels
# ---------------------------------------------------------------------------
isced <- c("8" = "doctorate", "7" = "master's degree", "6" = "bachelor's degree",
           "5" = "short tertiary degree", "4" = "post-secondary diploma",
           "3" = "upper secondary", "2" = "lower secondary")
short_label <- function(x) {
  parent <- str_match(x, "^Does your (mother|father) have.*ISCED level (\\d)")
  out <- ifelse(!is.na(parent[, 1]),
                paste0(str_to_title(parent[, 2]), " has a ", isced[parent[, 3]]), x)
  out <- out %>%
    str_replace("^How many books are there in your \\[home\\]\\?", "Number of books at home") %>%
    str_replace("^How many \\[digital devices\\] with screens.*", "Number of screens at home") %>%
    str_replace("^In the past 30 days, how often did you not eat.*", "Skipped meals: no money for food") %>%
    str_replace("^Now think about where you would place your family.*", "Family's perceived social standing") %>%
    str_replace("^Which of the following are in your \\[home\\]: ", "Has at home: ") %>%
    str_replace("^How many (of these items are there at|of the following \\[digital devices\\] are in) your \\[home\\]: ", "Number of ") %>%
    str_replace("^How many of these books at \\[home\\]: ", "") %>%
    str_remove_all("\\[|\\]") %>%
    str_remove(" \\([^)]*\\)") %>%
    str_replace("Your own cell phone with Internet access", "Own phone with internet") %>%
    str_remove(" that you can use for school work") %>%
    str_trunc(46)
  sub("^Number of ([A-Z])", "Number of \\L\\1", out, perl = TRUE)
}
top <- lasso %>%
  filter(subject == "Math", !is.na(mean_coef), mean_coef != 0) %>%
  slice_max(abs(mean_coef), n = 12) %>%
  mutate(short = short_label(label),
         short = factor(short, levels = short[order(mean_coef)]))
p_items <- ggplot(top, aes(mean_coef, short, fill = mean_coef > 0)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 0, color = "grey40") +
  geom_text(aes(label = sprintf("%+.0f", mean_coef),
                hjust = ifelse(mean_coef > 0, -0.2, 1.2)), size = 4.6, color = INK) +
  scale_fill_manual(values = c(`TRUE` = NAVY, `FALSE` = ORANGE), guide = "none") +
  scale_x_continuous(expand = expansion(mult = 0.15)) +
  labs(title = "What LASSO kept: the 12 strongest SES items (math)",
       subtitle = "Score points per item unit, averaged over 10 plausible values  |   U.S. students",
       x = "LASSO coefficient", y = NULL,
       caption = "Each item's effect is net of the other selected items.") +
  theme_showcase() + theme(panel.grid.major.y = element_blank(),
                           axis.text.y = element_text(size = 14, color = INK))
ggsave("plots/showcase_lasso_math.png", p_items, width = 12, height = 7, dpi = 150)

# ---------------------------------------------------------------------------
# 4. LASSO + OLS vs. KNN vs. the ESCS index
# ---------------------------------------------------------------------------
r2 <- metrics %>%
  filter(metric == "rsq_trad") %>%
  mutate(model = recode(model,
                        "OLS: ESCS only" = "ESCS index only",
                        "OLS: selected items" = "LASSO items + OLS",
                        "KNN: selected items" = "LASSO items + KNN"),
         model = factor(model, levels = c("ESCS index only", "LASSO items + OLS",
                                          "LASSO items + KNN")))
p_r2 <- ggplot(r2, aes(subject, mean, fill = model)) +
  geom_col(position = position_dodge(0.8), width = 0.72) +
  geom_errorbar(aes(ymin = min, ymax = max), position = position_dodge(0.8),
                width = 0.18, color = "grey25") +
  geom_text(aes(y = max + 0.012, label = sprintf("%.2f", mean)),
            position = position_dodge(0.8), vjust = 0, size = 5, color = INK) +
  scale_fill_manual(values = c(GREY, NAVY, ORANGE), name = NULL) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 0.47),
                     expand = expansion(mult = c(0, 0.02))) +
  labs(title = "SES items predict 2 to 3 times more than the ESCS index",
       subtitle = "Share of score variance explained on held-out U.S. students  |   whiskers: range over 10 plausible values",
       x = NULL, y = "R-squared (test set)") +
  theme_showcase() + theme(legend.position = "top", legend.justification = "left",
                           panel.grid.major.x = element_blank(),
                           axis.text.x = element_text(size = 15, color = INK))
ggsave("plots/showcase_models.png", p_r2, width = 12, height = 7, dpi = 150)

message("Done: plots/showcase_*.png and docs/index.html")
