# TITLE:            Species list query: pulling and summarizing GloBI interactions
# DATE:             August 26, 2026
# AUTHOR:           Lucas Mansfield
# OVERVIEW:         Given a species list, pull ALL GloBI interaction records for
#                   each species (as source taxon), drop the uninformative
#                   "interactsWith" interaction type, and summarize the unique
#                   records per species.
# DATA INPUT:       A dataframe containing a row for species scientific names
# DATA OUTPUT:      Per-species summary table (.csv)

rm(list = ls())
library(rglobi)
library(rgbif)
library(magrittr)
library(dplyr)
library(plyr)
library(stringr)
library(tidyr)
library(purrr)
library(readr)
library(progressr)

# !! SPECIFY LEVEL !! ##########################################################
level <- "IND"  # OBS = individual observations, IND = unique interactions only

species <- read.csv("data/taxa_TALL.csv")
species <- species %>% filter(taxonRank == "species",
                              taxonTypeCode != "BIRD")
species_list <- species$scientificName
species_list <- unique(species_list[!is.na(species_list) & species_list != ""])
species_table <- data.frame(scientific_name = species_list)



## MATCH TO GBIF BACKBONE
# Lookup function (uses possibly to catch errors with NULL)
safe_gbif_match <- possibly(function(name) {
  name_backbone(name = name, verbose = FALSE) %>%
    as_tibble()
}, otherwise = NULL)


# Set up a CLI progress bar (the following steps are LONGGG so this will be helpful for tracking)
handlers(handler_progress(
  format   = "[:bar] :percent | :current/:total taxa | ETA: :eta",
  width    = 60,
  complete = "="
))

with_progress({
  p <- progressor(steps = nrow(species_table))

  gbif_matches <- species_table %>%
    mutate(
      gbif_result = map(scientific_name, function(name) {
        p(message = sprintf("Querying: %s", name))
        safe_gbif_match(name)
      })
    )
})

# Unpack the gbif results (which until now are nested in a single cell)
gbif_matches <- unnest(gbif_matches, cols = c(gbif_result), names_sep = "_")

# Check alternatives for better matches
resolve_high_matches <- function(gbif_matches) {

  to_review <- gbif_matches %>% filter((gbif_result_rank %in% c("KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS")) &
                                         gbif_result_matchType %in% c("HIGHERRANK", "NONE"))

  if (nrow(to_review) == 0) {
    message("No high-rank matches to review.")
    return(gbif_matches)
  }

  resolved <- vector("list", nrow(to_review))

  for (i in seq_len(nrow(to_review))) {
    original_query <- to_review$scientific_name[i]
    matched_name <- to_review$gbif_result_canonicalName[i]

    cat("\n=====================================\n")
    cat(sprintf("[%d/%d] Queried name: %s\n", i, nrow(to_review), original_query))
    cat(sprintf("        Matched to: %s (rank: %s, matchType: %s)\n", matched_name, to_review$gbif_result_rank[i], to_review$gbif_result_matchType[i]))

    x <- tryCatch(name_backbone_verbose(name = original_query), error = function(e) NULL)

    if (is.null(x) || is.null(x$alternatives) || nrow(x$alternatives) == 0) {
      cat("No alternatives found. Keeping original match.\n")
      resolved[[i]] <- to_review[i, ]
      next
    }

    alts <- x$alternatives %>%
      select(any_of(c("usageKey", "scientificName", "rank", "status",
                      "matchType", "confidence", "kingdom", "phylum",
                      "class", "order", "family", "genus")))

    cat("Alternatives found:\n")
    for (j in seq_len(10)) {
      cat(sprintf("  [%d] %-35s rank=%-8s matchType=%-10s conf=%s  (%s)\n",
                  j, alts$scientificName[j], alts$rank[j],
                  alts$matchType[j], alts$confidence[j],
                  paste(na.omit(c(alts$family[j], alts$genus[j])), collapse = " > ")))
    }
    cat("  [0] Keep original match (no good alternative)\n")

    choice <- NA
    while (is.na(choice) || !(choice %in% 0:10)) {
      choice <- suppressWarnings(as.integer(readline("Select a match number: ")))
    }

    if (choice == 0) {
      resolved[[i]] <- to_review[i, ]
    } else {
      sel <- alts[choice, ]
      updated <- to_review[i, ]
      updated$gbif_result_rank           <- sel$rank
      updated$gbif_result_matchType      <- sel$matchType
      updated$gbif_result_usageKey       <- sel$usageKey
      updated$gbif_result_scientificName <- sel$scientificName
      resolved[[i]] <- updated
    }
  }

  resolved_df <- bind_rows(resolved)

  gbif_matches %>%
    filter(!(gbif_result_rank %in% c("KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS") &
               gbif_result_matchType %in% c("HIGHERRANK", "NONE"))) %>%
    bind_rows(resolved_df)
}

gbif_matches_checked <- resolve_high_matches(gbif_matches)

# Extract the important fields from GBIF backbone match
gbif_parsed <- gbif_matches_checked %>%
  transmute(
    queried_name       = scientific_name,
    gbif_key            = gbif_result_usageKey,
    match_type          = gbif_result_matchType,
    match_status        = gbif_result_status,
    accepted_name_GBIF  = gbif_result_canonicalName,
    species_GBIF       = gbif_result_species,
    genus_GBIF         = gbif_result_genus,
    family_GBIF        = gbif_result_family,
    order_GBIF         = gbif_result_order,
    class_GBIF         = gbif_result_class,
    phylum_GBIF        = gbif_result_phylum,
    rank_GBIF          = tolower(gbif_result_rank)
  )

# Create list of names to query on GloBI (both original and accepted names if different)
names_to_query <- gbif_parsed %>%
  transmute(
    queried_name = queried_name,
    accepted_name_GBIF = accepted_name_GBIF
  ) %>%
  pivot_longer(
    cols = everything(),
    names_to = "name_type",
    values_to = "query_name"
  ) %>%
  distinct(query_name, .keep_all = FALSE) %>%
  pull(query_name)

# Set up a CLI progress bar
handlers(handler_progress(
  format = "[:bar] :percent | :current/:total taxa | ETA: :eta",
  width = 60,
  complete = "="
))

# Pulling GloBI data!
if (level == "IND") {
  safe_get_interactions <- possibly(
    function(nm) {
      # Some plants are listed as variants (with taonomic authorities in their names) and don't query GloBI properly
      nm <- str_replace(nm, "^([^\\s]+\\s+[^\\s]+).*$", "\\1")
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

# Loop through all unique names (original + accepted)
with_progress({
  p <- progressor(steps = length(names_to_query))

  globi_results <- tibble(queried_name = names_to_query) %>%
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
  filter(interaction_type != "interactsWith",
         interaction_type != "coOccursWith",
         target_taxon_name != "Unknown")

# Map queried names back to their GBIF accepted names for grouping
name_mapping <- bind_rows(
  gbif_parsed %>% transmute(query_name = queried_name, accepted_name_GBIF),
  gbif_parsed %>% transmute(query_name = accepted_name_GBIF, accepted_name_GBIF)
) %>%
  distinct()

globi_filtered_mapped <- globi_filtered %>%
  left_join(
    name_mapping,
    by = c("queried_name" = "query_name"),
    relationship = "many-to-one"
  )

# Summarize unique records per species
# One row per GBIF accepted name, counting unique (source, interaction_type, target)
# combinations pulled for that species from both original and accepted name queries,
# plus a breakdown by interaction type.

species_summary <- globi_filtered_mapped %>%
  distinct(source_taxon_name, interaction_type, target_taxon_name, .keep_all = TRUE) %>%
  group_by(accepted_name_GBIF) %>%
  dplyr::summarise(
    n_unique_interactions = n(),
    n_unique_partners = n_distinct(target_taxon_name),
    interaction_types = paste(sort(unique(interaction_type)), collapse = "; "),
    .groups = "drop"
  )

# Make sure species with zero (non-interactsWith) records still show up as 0s
species_summary <- gbif_parsed %>%
  distinct(accepted_name_GBIF) %>%
  left_join(species_summary, by = "accepted_name_GBIF") %>%
  mutate(
    n_unique_interactions = replace_na(n_unique_interactions, 0),
    n_unique_partners = replace_na(n_unique_partners, 0),
    interaction_types = replace_na(interaction_types, "")
  )

merged <- left_join(gbif_parsed, species_summary, by = "accepted_name_GBIF")

# Adding common names from GBIF!
safe_common_name <- possibly(function(gbif_key) {

  name_usage(
    key = gbif_key,
    data = "vernacularNames"
  )$data %>%
    as_tibble() %>%
    filter(language == "eng") %>%
    pull(vernacularName) %>%
    first()

}, otherwise = NA_character_)

with_progress({
  p <- progressor(steps = nrow(merged))

  final <- merged %>%
    mutate(
      common_name = map_chr(gbif_key, function(name) {
        p(message = sprintf("Querying: %s", name))
        safe_common_name(name)
      })
    )
})


write_csv(final, "talllist.csv")
