# 05 — SES gradients for the README
# How U.S. math scores change with family background: by ESCS decile, by the
# number of books at home, and by how often students skipped meals.
# Weighted with W_FSTUWT; each mean is computed per plausible value and the
# 10 results are averaged.
#
# Requires: data/analysis_data.rds (from 01)
# Writes:   plots/showcase_gradients.png
# Run from the repository root.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

usa <- readRDS("data/analysis_data.rds") %>%
  filter(CNT == "USA") %>%
  mutate(across(any_of(c("ST255Q01JA", "ST258Q01JA")), ~ as.numeric(.x)))

# Weighted mean math score per group, averaged over the 10 plausible values
pv_mean <- function(df) {
  mean(sapply(1:10, function(k)
    weighted.mean(df[[paste0("PV", k, "MATH")]], df$W_FSTUWT, na.rm = TRUE)))
}
gradient <- function(df, group, labels, panel) {
  df %>%
    mutate(g = round(.data[[group]])) %>%
    filter(g %in% seq_along(labels)) %>%
    group_by(g) %>%
    group_modify(~ tibble(score = pv_mean(.x), n = nrow(.x))) %>%
    ungroup() %>%
    mutate(label = labels[g], panel = panel)
}

escs_dec <- usa %>%
  filter(!is.na(ESCS)) %>%
  mutate(decile = ntile(ESCS, 10))
grad <- bind_rows(
  gradient(escs_dec, "decile", paste0("D", 1:10),
           "By family background (ESCS decile)"),
  gradient(usa, "ST255Q01JA",
           c("0", "1-10", "11-25", "26-100", "101-200", "201-500", "500+"),
           "By number of books at home"),
  gradient(usa %>% mutate(food = pmin(round(ST258Q01JA), 4)), "food",
           c("Never", "Weekly", "2-3/week", "4+/week"),
           "By how often they skipped meals (no money for food)")
) %>%
  mutate(panel = factor(panel, levels = unique(panel)),
         key = factor(paste(panel, g), levels = unique(paste(panel, g))))

ends <- grad %>% group_by(panel) %>% filter(g == min(g) | g == max(g))
gap  <- grad %>% group_by(panel) %>%
  summarise(diff = score[g == max(g)] - score[g == min(g)], .groups = "drop") %>%
  mutate(txt = sprintf("%+.0f points", diff))

NAVY <- "#1b3a6b"; INK <- "#1f2a3a"
p <- ggplot(grad, aes(key, score, group = panel)) +
  geom_line(color = NAVY, linewidth = 1.4) +
  geom_point(color = NAVY, size = 3.4) +
  geom_text(data = ends, aes(label = round(score)), vjust = -1.1, size = 4.6,
            color = INK, fontface = "bold") +
  geom_text(data = gap, aes(x = -Inf, y = Inf, label = txt), inherit.aes = FALSE,
            hjust = -0.15, vjust = 1.6, size = 5, color = "#e8862a", fontface = "bold") +
  facet_wrap(~ panel, scales = "free_x", nrow = 1,
             labeller = label_wrap_gen(width = 30)) +
  scale_x_discrete(labels = setNames(grad$label, grad$key)) +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.18))) +
  labs(title = "Family background and math scores: U.S. students, PISA 2022",
       subtitle = "Weighted mean math score, averaged over 10 plausible values",
       x = NULL, y = "Mean math score") +
  theme_minimal(base_size = 15) +
  theme(plot.title = element_text(face = "bold", size = 20, color = INK),
        plot.subtitle = element_text(color = "grey35", margin = margin(b = 10)),
        plot.title.position = "plot",
        strip.text = element_text(face = "bold", size = 13, color = INK, hjust = 0),
        panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
        axis.text.x = element_text(size = 11, angle = 35, hjust = 1),
        panel.spacing = unit(1.5, "lines"),
        plot.background = element_rect(fill = "white", color = NA),
        plot.margin = margin(14, 18, 10, 14))

# Group sizes, to check the categories look right
print(grad %>% select(panel, label, n, score), n = 30)

ggsave("plots/showcase_gradients.png", p, width = 14, height = 6.5, dpi = 150)
message("Done: plots/showcase_gradients.png")
