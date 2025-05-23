## ----------------------------------------------------------------------------
## SET UP THE ENVIRONMENT

## Load in the R packages used in this script from the project library.
library(ggplot2)
library(dplyr)
library(tidyr)
library(stringr)
library(RColorBrewer)
library(zoo)
library(cowplot)
library(crayon)


## ----------------------------------------------------------------------------
## LOAD IN THE DATA

gwas_header <- colnames(
  read.delim(
    "gwas_catalog-ancestry_r2025-05-13.tsv",
    header = T,
    sep = '\t',
    row.names = NULL
  )
)

gwas <- read.delim(
  "gwas_catalog-ancestry_r2025-05-13.tsv",
  header = F,
  sep = '\t',
  skip = 1
)[, 1:12] %>% `colnames<-`(gwas_header[1:12])

gwas$DATE <- as.Date(gwas$DATE)


## ----------------------------------------------------------------------------
## DATA PREPARATION

# Order GWAS catalog by date
gwas <- gwas %>% arrange(DATE)

# Group individuals by broad ancestral categories
gwas_easy <- gwas[!grepl(', ', gwas$BROAD.ANCESTRAL.CATEGORY) &
                    gwas$BROAD.ANCESTRAL.CATEGORY != 'NR', ]

mideast <- gwas[gwas$BROAD.ANCESTRAL.CATEGORY == 'Greater Middle Eastern (Middle Eastern, North African or Persian)', ]

africa <- gwas[gwas$BROAD.ANCESTRAL.CATEGORY %in% c(
  'Sub-Saharan African, African American or Afro-Caribbean',
  'Sub-Saharan African, African unspecified',
  'African American or Afro-Caribbean, African unspecified'
), ]
africa$BROAD.ANCESTRAL.CATEGORY <- 'African unspecified'

asia <-
  gwas[gwas$BROAD.ANCESTRAL.CATEGORY %in% c(
    'East Asian, Asian unspecified',
    'East Asian, South Asian',
    'East Asian, South Asian, South East Asian',
    'East Asian, South East Asian, South Asian, Asian unspecified',
    'South Asian, East Asian',
    'South Asian, South East Asian',
    'South Asian, South East Asian, East Asian',
    'South East Asian, East Asian',
    'South East Asian, South Asian, East Asian',
    'South Asian, South East Asian, East Asian, Asian unspecified',
    'South Asian, Central Asian',
    'Asian unspecified, East Asian',
    'Central Asian, South Asian'
  ), ]
asia$BROAD.ANCESTRAL.CATEGORY <- 'Asian unspecified'

nr <- gwas[gwas$BROAD.ANCESTRAL.CATEGORY == 'NR', ]

multiple <-
  gwas[grepl(', ', gwas$BROAD.ANCESTRAL.CATEGORY) &
         gwas$BROAD.ANCESTRAL.CATEGORY != 'NR' &
         gwas$BROAD.ANCESTRAL.CATEGORY != 'Greater Middle Eastern (Middle Eastern, North African or Persian)' &
         !gwas$BROAD.ANCESTRAL.CATEGORY %in% c(
           'Sub-Saharan African, African American or Afro-Caribbean',
           'Sub-Saharan African, African unspecified',
           'African American or Afro-Caribbean, African unspecified'
         ) &
         !gwas$BROAD.ANCESTRAL.CATEGORY %in% c(
           'East Asian, Asian unspecified',
           'East Asian, South Asian',
           'East Asian, South Asian, South East Asian',
           'East Asian, South East Asian, South Asian, Asian unspecified',
           'South Asian, East Asian',
           'South Asian, South East Asian',
           'South Asian, South East Asian, East Asian',
           'South East Asian, East Asian',
           'South East Asian, South Asian, East Asian',
           'South Asian, South East Asian, East Asian, Asian unspecified',
           'South Asian, Central Asian',
           'Asian unspecified, East Asian',
           'Central Asian, South Asian'
         ) &
         gwas$BROAD.ANCESTRAL.CATEGORY != 'NR', ]

multiple$BROAD.ANCESTRAL.CATEGORY <- 'Multiple'

gwas_simplified <- bind_rows(gwas_easy, mideast, africa, asia, nr, multiple)

# Create broad ancestral categories
anc_categories <-
  data.frame(
    ancestry = sort(unique(
      gwas_simplified$BROAD.ANCESTRAL.CATEGORY
    )),
    category = c(
      rep('Non-EURASN', 3),
      rep('ASN', 3),
      'EUR',
      rep('Non-EURASN', 2),
      'Multiple',
      'Non-EURASN',
      'NR',
      rep('Non-EURASN', 3),
      rep('ASN', 2),
      'Non-EURASN'
    ),
    category2 = c(
      'Oceanic',
      rep('African', 2),
      rep('South Asian/Other Asian', 2),
      'East Asian',
      'European',
      'Greater Middle Eastern',
      'Hispanic/Latino',
      'Multiple',
      'Other',
      'Not Reported',
      'Oceanic',
      rep('Other', 2),
      rep('South Asian/Other Asian', 2),
      'African'
    )
  )

# Merge the categories with the original dataset
anc_merge <- merge(gwas_simplified, anc_categories, by.x = 'BROAD.ANCESTRAL.CATEGORY', 'ancestry')
anc_merge$category2 <-
  factor(anc_merge$category2, levels = (
    c(
      'European',
      'East Asian',
      'South Asian/Other Asian',
      'African',
      'Hispanic/Latino',
      'Greater Middle Eastern',
      'Oceanic',
      'Other',
      'Multiple',
      'Not Reported'
    )
  )) #rev
anc_merge <- subset(anc_merge, category2 != 'Not Reported')

## Case 1: Same PUBMEDID, STAGE, category2, NUMBER.OF.IDIVIDUALS
anc_merge_dupl <- anc_merge %>%
  select(
    STUDY.ACCESSION,
    PUBMEDID,
    FIRST.AUTHOR,
    DATE,
    INITIAL.SAMPLE.DESCRIPTION,
    REPLICATION.SAMPLE.DESCRIPTION,
    STAGE,
    NUMBER.OF.INDIVDUALS,
    BROAD.ANCESTRAL.CATEGORY,
    category2
  ) %>%
  distinct(PUBMEDID, STAGE, category2, NUMBER.OF.INDIVDUALS, .keep_all = TRUE)

# Case 2: Specific PUBMEDID with large numbers of duplicate-counts
## One ancestry category for 30104761 and 34662886
target_pubmedids <- c(30104761, 34662886)
extract_control_size <- function(description) {
  description <- gsub(",", "", description)
  match_controls <- str_extract(description, "\\d+(?=\\s*[^\\d]*controls)")
  if (!is.na(match_controls)) {
    return(as.numeric(match_controls))
  } else {
    match_number <- str_extract(description, "\\d+")
    if (!is.na(match_number)) {
      return(as.numeric(match_number))
    } else {
      return(NA)
    }
  }
}
anc_merge_dupl <- anc_merge_dupl %>%
  mutate(
    control_size_initial =
      ifelse(
        PUBMEDID %in% target_pubmedids & STAGE == "initial",
        sapply(INITIAL.SAMPLE.DESCRIPTION, extract_control_size),
        NA
      ),
    control_size_replication =
      ifelse(
        PUBMEDID %in% target_pubmedids & STAGE == "replication",
        sapply(REPLICATION.SAMPLE.DESCRIPTION, extract_control_size),
        NA
      )
  ) %>%
  group_by(PUBMEDID) %>%
  mutate(
    control_size_row = ifelse(
      PUBMEDID %in% target_pubmedids,
      pmax(control_size_initial, control_size_replication, na.rm = TRUE),
      NA
    ),
    adjusted_individuals = ifelse(
      !is.na(control_size_row),
      pmax(NUMBER.OF.INDIVDUALS - control_size_row, 0),
      NUMBER.OF.INDIVDUALS
    ),
    is_last_row = row_number() == n(),
    max_control_size = ifelse(
      PUBMEDID %in% target_pubmedids,
      max(control_size_row, na.rm = TRUE),
      NA
    ),
  ) %>%
  mutate(
    adjusted_individuals = ifelse(
      is_last_row & !is.na(control_size_row),
      adjusted_individuals + max_control_size,
      adjusted_individuals
    )
  ) %>%
  ungroup() %>%
  mutate(
    NUMBER.OF.INDIVDUALS = ifelse(
      PUBMEDID %in% target_pubmedids,
      adjusted_individuals,
      NUMBER.OF.INDIVDUALS
    )
  )

## Multiple ancestry group for 34888493 and no specification for case and control
# Define target PUBMEDID
target_pubmedid <- 32888493

# Define ancestry categories
target_ancestries <- c(
  "East Asian",
  "Hispanic or Latin American",
  "South Asian",
  "African American or Afro-Caribbean and African",
  "European"
)

# Remove rows with the combined category
anc_merge_dupl <- anc_merge_dupl %>%
  filter(!(
    PUBMEDID == target_pubmedid &
      str_detect(
        INITIAL.SAMPLE.DESCRIPTION,
        "African American or Afro-Caribbean, African ancestry, European ancestry, East Asian ancestry, Hispanic or Latin American and South Asian ancestry individuals"
      )
  ))

# Process remaining rows
anc_merge_dupl <- anc_merge_dupl %>%
  mutate(adjusted_individuals = ifelse(PUBMEDID == target_pubmedid, 0, NUMBER.OF.INDIVDUALS)) %>%
  group_by(PUBMEDID, BROAD.ANCESTRAL.CATEGORY) %>%
  mutate(
    is_last_row = row_number() == n(),
    max_individuals = max(NUMBER.OF.INDIVDUALS, na.rm = TRUE)
  ) %>%
  mutate(
    adjusted_individuals = ifelse(
      is_last_row & PUBMEDID == target_pubmedid,
      max_individuals,
      adjusted_individuals
    )
  ) %>%
  ungroup() %>%
  mutate(
    NUMBER.OF.INDIVDUALS = ifelse(
      PUBMEDID == target_pubmedid,
      adjusted_individuals,
      NUMBER.OF.INDIVDUALS
    )
  )

## Multiple ancestry categories and multiple types of description for 34594039 and 39024449
# Define the target PUBMEDID
target_pubmedid <- 34594039

# Process dataset
anc_merge_dupl <- anc_merge_dupl %>%
  # Remove case/control rows (Keep only "individuals" rows)
  filter(!(
    PUBMEDID == target_pubmedid &
      grepl("cases|controls", INITIAL.SAMPLE.DESCRIPTION, ignore.case = TRUE)
  )) %>%
  
  # Set adjusted_individuals to 0 for all target PUBMEDID rows initially
  mutate(adjusted_individuals = ifelse(PUBMEDID == target_pubmedid, 0, NUMBER.OF.INDIVDUALS)) %>%
  
  # Group by PUBMEDID and ancestry category to process each ancestry separately
  group_by(PUBMEDID, BROAD.ANCESTRAL.CATEGORY) %>%
  
  # Identify last row for each ancestry category
  mutate(
    is_last_row = row_number() == n(),
    max_individuals = max(NUMBER.OF.INDIVDUALS, na.rm = TRUE) # Get max individuals for the ancestry category
  ) %>%
  
  # Assign max individual count to the last row of each ancestry
  mutate(
    adjusted_individuals = ifelse(
      is_last_row & PUBMEDID == target_pubmedid,
      max_individuals,
      adjusted_individuals
    )
  ) %>%
  
  ungroup() %>%
  
  # Assign final values
  mutate(
    NUMBER.OF.INDIVDUALS = ifelse(
      PUBMEDID == target_pubmedid,
      adjusted_individuals,
      NUMBER.OF.INDIVDUALS
    )
  )

# Define the target PUBMEDID
target_pubmedid <- 39024449

# Process dataset
anc_merge_dupl <- anc_merge_dupl %>%
  # Remove case/control rows (Keep only "individuals" rows)
  filter(!(
    PUBMEDID == target_pubmedid &
      grepl("cases|controls", INITIAL.SAMPLE.DESCRIPTION, ignore.case = TRUE)
  )) %>%
  
  # Set adjusted_individuals to 0 for all target PUBMEDID rows initially
  mutate(adjusted_individuals = ifelse(PUBMEDID == target_pubmedid, 0, NUMBER.OF.INDIVDUALS)) %>%
  
  # Group by PUBMEDID and ancestry category to process each ancestry separately
  group_by(PUBMEDID, BROAD.ANCESTRAL.CATEGORY) %>%
  
  # Identify last row for each ancestry category
  mutate(
    is_last_row = row_number() == n(),
    max_individuals = max(NUMBER.OF.INDIVDUALS, na.rm = TRUE) # Get max individuals for the ancestry category
  ) %>%
  
  # Assign max individual count to the last row of each ancestry
  mutate(
    adjusted_individuals = ifelse(
      is_last_row & PUBMEDID == target_pubmedid,
      max_individuals,
      adjusted_individuals
    )
  ) %>%
  
  ungroup() %>%
  
  # Assign final values
  mutate(
    NUMBER.OF.INDIVDUALS = ifelse(
      PUBMEDID == target_pubmedid,
      adjusted_individuals,
      NUMBER.OF.INDIVDUALS
    )
  )


## Cleaned Dataset
gwas_pop_date_agg <-
  anc_merge_dupl %>%
  select(
    STUDY.ACCESSION,
    PUBMEDID,
    FIRST.AUTHOR,
    DATE,
    STAGE,
    NUMBER.OF.INDIVDUALS,
    BROAD.ANCESTRAL.CATEGORY,
    category2
  ) %>%
  arrange(DATE) %>%
  subset(!is.na(NUMBER.OF.INDIVDUALS)) %>%
  group_by(category2) %>%
  mutate(date_total = cumsum(as.numeric(NUMBER.OF.INDIVDUALS))) %>%
  group_by(DATE, category2) %>%
  slice(which.max(date_total))

# Set colors for population plot
color_vec <- c(brewer.pal(4, 'Set1'), 'grey')
color_vec <- c(
  color_vec,
  brewer.pal(3, 'Reds')[2:3],
  color_vec[2],
  brewer.pal(5, 'Greens')[2:5],
  color_vec[4],
  'grey'
)
names(color_vec) <- (
  c(
    'ASN',
    'EUR',
    'Non-EURASN',
    'Multiple',
    'NR',
    'East Asian',
    'Other Asian',
    'European',
    'African',
    'Hispanic or Latin American',
    'MidNatOce',
    'Other',
    'Multiple',
    'NR'
  )
)

color_vec <- c(brewer.pal(8, 'Set1'), brewer.pal(3, 'Greys')[2:3])
labels <- levels(anc_merge_dupl$category2)
names(color_vec) <- labels

my_vals <- gwas_pop_date_agg %>%
  arrange(DATE) %>%
  ungroup() %>%
  expand(DATE, category2) %>%
  distinct()
my_vals2 <- merge(my_vals,
                  gwas_pop_date_agg,
                  all.x = T,
                  by = c('DATE', 'category2'))
my_vals2$date_total[2:10] <- 0
my_vals2 <- my_vals2 %>%
  subset(category2 != 'Not Reported') %>%
  group_by(category2) %>%
  mutate(fill_gap = na.locf(date_total, fromLast = F, na.rm = F))
# na.locf is filling from the wrong direction. later dates first
my_vals3 <- my_vals2 %>%
  subset(category2 != 'Not Reported') %>%
  group_by(DATE) %>%
  mutate(pop_frac = fill_gap / sum(fill_gap))

##### Calculate proportions
target_date <- as.Date("2025-04-25")
target_category <- "East Asian"

category_fraction <- my_vals2 %>%
  filter(DATE == target_date) %>%
  group_by(DATE) %>%
  mutate(total_fill_gap = sum(fill_gap, na.rm = TRUE)) %>%
  filter(category2 == target_category) %>%
  summarise(proportion = fill_gap / total_fill_gap)

print(category_fraction)

specific_pop_frac <- my_vals3 %>%
  filter(DATE == target_date & category2 == target_category) %>%
  select(DATE, category2, pop_frac)

print(specific_pop_frac)

proportions_at_date <- my_vals3 %>%
  filter(DATE == target_date) %>%
  select(category2, pop_frac)

print(proportions_at_date)
# 
# my_vals2 %>%
#   filter(DATE == target_date) %>%
#   group_by(DATE) %>%
#   mutate(total_fill_gap = sum(fill_gap, na.rm = TRUE)) %>%
#   select(total_fill_gap)
# 
# daily_change <- my_vals2 %>%
#   arrange(category2, DATE) %>%
#   group_by(category2) %>%
#   mutate(delta = fill_gap - lag(fill_gap)) %>%
#   ungroup()
# 
# daily_change %>%
#   filter(category2 == "East Asian") %>%
#   filter(!is.na(delta)) %>%
#   arrange(desc(delta)) %>%
#   slice_head(n = 10)
# 
# top_changes <- daily_change %>%
#   filter(!is.na(delta)) %>%
#   arrange(desc(delta)) %>%
#   slice_head(n = 20)
# 
# center_date <- as.Date("2024-07-19")
# window_days <- 5
# 
# subset_vals <- my_vals2 %>%
#   filter(DATE >= center_date - window_days &
#            DATE <= center_date + window_days)
# 
# ggplot(subset_vals, aes(x = DATE, y = fill_gap / 1e6, fill = category2)) +
#   geom_area(position = "stack") +
#   scale_fill_manual(values = color_vec, name = "Ancestry Category") +
#   labs(x = "Date", y = "Individuals in GWAS (millions)") +
#   theme_classic() +
#   theme(axis.text = element_text(color = 'black'),
#         legend.position = "bottom")
# 
# start_date <- as.Date("2024-07-16")
# end_date <- as.Date("2024-07-19")
# 
# anc_merge_dupl %>%
#   filter(DATE >= start_date & DATE <= end_date) %>%
#   select(
#     DATE,
#     PUBMEDID,
#     FIRST.AUTHOR,
#     NUMBER.OF.INDIVDUALS,
#     category2,
#     INITIAL.SAMPLE.DESCRIPTION
#   ) %>%
#   arrange(desc(NUMBER.OF.INDIVDUALS))

#####

p2 <- ggplot(my_vals2,
             aes(
               x = DATE,
               y = fill_gap / 1e6,
               fill = category2,
               color = category2
             )) +
  geom_area(position = 'stack') +
  scale_x_date(date_breaks = "2 years",
               date_labels = "%Y",
               limits = as.Date(c("2005-01-01", "2025-04-25"))) +
  scale_fill_manual(values = color_vec, name = 'Ancestry Category') +
  scale_color_manual(values = color_vec, name = 'Ancestry Category') +
  labs(x = '', y = 'Individuals in GWAS (millions)') +
  theme_classic() +
  theme(
    axis.text = element_text(color = 'black'),
    axis.text.x = element_text(
      angle = 0,
      vjust = 0.5,
      hjust = 0.5
    ),
    text = element_text(size = 12),
    legend.position = c(0.02, 1),
    legend.justification = c(0, 1),
    legend.text = element_text(size = 10),
    legend.background = element_rect(fill = "transparent", colour = NA)
  )

p3 <- ggplot(my_vals3,
             aes(
               x = DATE,
               y = pop_frac,
               fill = category2,
               color = category2
             )) +
  geom_area(position = 'stack') +
  scale_x_date(date_breaks = "2 years",
               date_labels = "%Y",
               limits = as.Date(c("2005-01-01", "2025-04-25")),
               position = 'top') +
  scale_fill_manual(values = color_vec, name = 'Ancestry Category') +
  scale_color_manual(values = color_vec, name = 'Ancestry Category') +
  labs(x = '', y = 'Proportion') +
  theme_classic() +
  guides(fill = F, color = F) +
  theme(
    axis.text = element_text(color = 'black'),
    axis.text.x = element_blank(),
    text = element_text(size = 12),
    panel.background = element_rect(fill = "transparent", colour = NA),
    plot.background = element_rect(fill = "transparent", colour = NA)
  ) +
  annotate(
    "text",
    x = mean(range(my_vals3$DATE)),
    y = -0.05,
    label = "Year",
    size = 4.5,
    hjust = 0.5
  )


# http://www.worldometers.info/world-population/#region (May 20)
populationAncestries <-
  data.frame(
    pop = c(
      "East Asian",
      "South Asian/Other Asian",
      "European",
      "Greater Middle Eastern",
      "African",
      "Hispanic/Latino",
      "Oceanic"
    ),
    world = c(
      1652185615,
      2785239416,
      744398832,
      590599485,
      1273565325,
      667888552,
      46609644
    )
  )
populationAncestries$proportion <- populationAncestries$world / 8231613070

#### Proportions for each category
rbind(populationAncestries$pop,
      round(
        populationAncestries$world / sum(populationAncestries$world),
        4
      ))
####

populationAncestries <- populationAncestries %>%
  mutate(total_world = cumsum(world), min_world = total_world - world)
populationAncestries$pop <-
  factor(populationAncestries$pop, levels = rev(
    c(
      'Oceanic',
      'Greater Middle Eastern',
      'Hispanic/Latino',
      'African',
      'South Asian/Other Asian',
      'East Asian',
      'European'
    )
  ))
p_global <- ggplot(populationAncestries,
                   aes(
                     x = 'Present',
                     y = world / 1000000000,
                     fill = pop
                   )) +
  geom_bar(stat = 'identity') +
  theme_classic() +
  scale_fill_manual(values = color_vec) +
  labs(y = 'Global population (billions)', x = '') +
  guides(fill = F) +
  scale_y_continuous(position = 'right') +
  theme(
    axis.text = element_text(color = 'black'),
    axis.text.x = element_text(angle = 0, vjust = 0.5),
    text = element_text(size = 12)
  )

p_global2 <- p_global +
  scale_x_discrete(position = 'top') +
  labs(y = '', x = '') +
  theme(
    axis.text = element_text(color = 'black'),
    axis.text.x = element_blank(),
    axis.text.y = element_text(color = 'white'),
    axis.ticks.y = element_blank(),
    plot.background = element_rect(fill = "transparent", colour = NA)
  )

p_gwas_global <- plot_grid(p2,
                           p_global,
                           align = "h",
                           rel_widths = c(0.85, 0.15))
p_gwas_global2 <- plot_grid(p3,
                            p_global2,
                            align = "h",
                            rel_widths = c(0.85, 0.15))
p_agg <- ggdraw() +
  draw_plot(p_gwas_global, 0, 0.3, 1, 0.68) +
  draw_plot(p_gwas_global2, 0, 0, 1, 0.35)
p_agg
# save_plot('gwas.pdf', p_agg, base_width=14, base_height=10)
ggsave(
  "gwas.png",
  plot = p_agg,
  width = 14,
  height = 10,
  dpi = 800
)
