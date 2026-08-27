# TITLE:            Species list query: pulling and summarizing GloBI interactions
# DATE:             August 26, 2026
# AUTHOR:           Lucas Mansfield
# OVERVIEW:         Given a species list, pull ALL GloBI interaction records for
#                    each species (as source taxon), drop the uninformative
#                    "interactsWith" interaction type, and summarize the unique
#                    records per species.
# DATA INPUT:       A dataframe containing a row for species scientific names
# DATA OUTPUT:      Per-species summary table (.csv)

rm(list = ls())
library(rglobi)
library(magrittr)
library(dplyr)
library(plyr)
library(stringr)
library(tidyr)
library(purrr)
library(progressr)

# !! SPECIFY LEVEL !! ##########################################################
level <- "IND"  # OBS = individual observations, IND = unique interactions only

species <- read.csv("data/birds.csv")
species_list <- species$scientific_name
species_list <- unique(species_list[!is.na(species_list) & species_list != ""])

# Set up a CLI progress bar (pulling is slow, so this helps with tracking)
handlers(handler_progress(
  format = "[:bar] :percent | :current/:total taxa | ETA: :eta",
  width = 60,
  complete = "="
))

# Pulling GloBI data!
if (level == "IND") {
  safe_get_interactions <- possibly(
    function(nm) {
      get_interactions_by_taxa(
        sourcetaxon = nm,
        returnobservations = FALSE,
        otherkeys = list(limit = 100000),
        showfield = c("source_taxon_name", "interaction_type", "target_taxon_name")
      ) %>% distinct()
    },
    otherwise = NULL
  )
} else {
  safe_get_interactions <- possibly(
    function(nm) {
      get_interactions_by_taxa(
        sourcetaxon = nm,
        returnobservations = TRUE,
        otherkeys = list(limit = 100000),
        showfield = c("source_taxon_name", "source_specimen_life_stage",
                      "interaction_type", "target_taxon_name",
                      "target_specimen_life_stage", "latitude", "longitude",
                      "altitude", "locality", "event_date", "study_url", "study_citation")
      ) %>% distinct()
    },
    otherwise = NULL
  )
}

# Loop through all species on list
with_progress({
  p <- progressor(steps = length(species_list))
  
  globi_results <- tibble(queried_name = species_list) %>%
    mutate(
      globi_data = map(queried_name, function(nm) {
        p()
        result <- safe_get_interactions(nm)
        if (!is.null(result) && nrow(result) > 0) {
          result %>% mutate(matched_query = nm)
        } else {
          NULL
        }
      })
    )
})

globi_long_raw <- ldply(
  setNames(globi_results$globi_data, globi_results$queried_name),
  .id = "queried_name"
) %>%
  select(!matched_query)

globi_long_raw <- globi_long_raw %>%
  mutate(interaction_ID = seq_len(nrow(globi_long_raw)))

# Clean and deduplicate rows
globi_long <- globi_long_raw %>%
  filter(!is.na(target_taxon_name)) %>%
  filter(!str_detect(target_taxon_name, "^-?\\d+\\.?\\d*$")) %>%
  distinct(across(-queried_name), .keep_all = TRUE)

# Drop "interactsWith"
# interactsWith is GloBI's catch-all/unspecified interaction type and isn't
# informative for us, so it's excluded here (same as Swiss metaweb paper).
globi_filtered <- globi_long %>%
  filter(interaction_type != "interactsWith")

# Summarize unique records per species
# One row per species queried, counting unique (source, interaction_type, target)
# combinations pulled for that species, plus a breakdown by interaction type.

species_summary <- globi_filtered %>%
  distinct(source_taxon_name, interaction_type, target_taxon_name, .keep_all = TRUE) %>%
  group_by(source_taxon_name) %>%
  dplyr::summarise(
    n_unique_interactions = n(),
    n_unique_partners = n_distinct(target_taxon_name),
    interaction_types = paste(sort(unique(interaction_type)), collapse = "; "),
    .groups = "drop"
  )

# Make sure species with zero (non-interactsWith) records still show up as 0s
species_summary <- tibble(source_taxon_name = species_list) %>%
  left_join(species_summary, by = "source_taxon_name") %>%
  mutate(
    n_unique_interactions = replace_na(n_unique_interactions, 0),
    n_unique_partners = replace_na(n_unique_partners, 0),
    interaction_types = replace_na(interaction_types, "")
  )

print(species_summary)