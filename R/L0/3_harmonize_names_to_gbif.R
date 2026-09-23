# TITLE:            harmonize_names_to_gbif.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:
# DATA INPUT:       (1) `df`, the output of 2_harmonize_datasheet_versions.R
#                       -- must have taxa1_scientific/taxa1_group and
#                       taxa2_scientific/taxa2_group columns.
#                   (2) optional 3_gbif_manual_matches.csv manual-correction
#                       CSV (created by this script, edited by hand, re-read
#                       on the next run).
# DATA OUTPUT:      `crosswalk`, one row per unique MetaNetworks raw_name,
#                   matched against the GBIF backbone with a match_status,
#                   final_usageKey, and resolved taxonomic hierarchy;
#                   `crosswalk_new`, the same with an n_avilist_rows match
#                   count added. 3_gbif_manual_matches.csv (review
#                   template / correction registry, written to disk).
# DATE:             initiated: unknown -- predates this header, please
#                   backfill from version control if available; last
#                   updated: 23 September 2026.
# OVERVIEW:         Classifies each raw MetaNetworks taxon name (full name /
#                   higher-rank-expected / excluded), matches it against the
#                   GBIF backbone -- optionally constrained by taxa_group
#                   (e.g. bird names searched within class Aves) -- and
#                   triages the result into an automatic match or a row
#                   needing manual review. Supports a hand-edited
#                   manual-match correction registry
#                   (3_gbif_manual_matches.csv) that overrides an automated
#                   match by usageKey and backfills its hierarchy via a live
#                   GBIF lookup.
# REQUIRES:         2_harmonize_datasheet_versions.R must have already
#                   produced `df`. rgbif, tidyverse. avilistr, for the
#                   exploratory AviList match-count step at the bottom.
#                   harmonize_names_to_checklist.R consumes this script's
#                   `crosswalk` downstream, and expects it to already be
#                   fully reviewed and corrected (i.e. run this script's
#                   whole build -> export -> hand-fill -> apply cycle first).
# NOTES:            2026-09-21: match_status now sends a "higher-rank-expected"
#                   query (bare genus, "sp.", "unid.", ...) to manual review
#                   ("needs_review_coarsest_group_only") when GBIF can only
#                   resolve it to the taxa_group's own coarsest filter rank
#                   (e.g. a bare "bird" entry resolving to nothing finer than
#                   class Aves) rather than auto-accepting it as "matched".
#                   2026-09-21: the GBIF-hop manual-match tooling
#                   (taxa_lookup_gbif_usage(), taxa_export_gbif_review_template(),
#                   taxa_apply_gbif_manual_matches()) moved here from
#                   harmonize_names_to_checklist.R -- it's pure GBIF-crosswalk
#                   logic with nothing checklist-specific about it.
#                   2026-09-23: GBIF usage keys are alphanumeric now, not
#                   guaranteed integer -- removed the as.integer() coercion
#                   on manual_gbif_usageKey in taxa_apply_gbif_manual_matches()
#                   that broke on the new key format.

library(rgbif)
library(tidyverse)

# ---- 0. taxa_group -> GBIF classification filter -----------------------------

# Which GBIF rank field constrains a group's search. Shared by
# taxa_group_to_gbif_filter() (the search-time constraint) and the
# match_status logic in taxa_build_gbif_crosswalk() below (detecting a match
# that only reached that constraint and nothing finer).
taxa_group_to_gbif_rank_field <- function(taxa_group) {
  dplyr::case_when(
    taxa_group %in% c("bird", "mammal", "amphibian", "reptile") ~ "class",
    taxa_group %in% c("mollusk", "arthropod") ~ "phylum",
    taxa_group %in% c("plant", "fungus") ~ "kingdom",
    TRUE ~ NA_character_ # fish, worm, protist, or unrecognized -- no filter
  )
}

taxa_group_to_gbif_filter <- function(taxa_group) {
  filter_field <- taxa_group_to_gbif_rank_field(taxa_group)

  filter_value <- dplyr::case_when(
    taxa_group == "bird" ~ "Aves",
    taxa_group == "mammal" ~ "Mammalia",
    taxa_group == "amphibian" ~ "Amphibia",
    taxa_group == "reptile" ~ "Reptilia",
    taxa_group == "mollusk" ~ "Mollusca",
    taxa_group == "arthropod" ~ "Arthropoda",
    taxa_group == "plant" ~ "Plantae",
    taxa_group == "fungus" ~ "Fungi",
    TRUE ~ NA_character_
  )

  data.frame(
    kingdom = dplyr::if_else(
      filter_field == "kingdom",
      filter_value,
      NA_character_
    ),
    phylum = dplyr::if_else(
      filter_field == "phylum",
      filter_value,
      NA_character_
    ),
    class = dplyr::if_else(
      filter_field == "class",
      filter_value,
      NA_character_
    ),
    stringsAsFactors = FALSE
  )
}
# ---- 1. Classify each unique name before it ever hits GBIF ------------------
taxa_classify_name_string <- function(raw_name) {
  clean_name <- stringr::str_squish(raw_name)
  word_count <- stringr::str_count(clean_name, "\\S+")

  # cf./aff. (tentative ID) and numbered/lettered morphospecies codes --
  # neither will resolve to a real GBIF taxon, so these never get queried
  is_excluded <- stringr::str_detect(
    clean_name,
    "\\bcf\\.?\\b|\\baff\\.?\\b|\\bsp{1,2}\\.\\s*[0-9A-Za-z]+$"
  )

  # sp./spp./unid./indet. qualifier, written before OR after the taxon name
  # -- "unid. Vireonidae" and "Vireonidae unid." both need to match here
  qualifier <- "(sp{1,2}|unid|indet)"
  qualifier_pattern <- stringr::str_c(
    "^",
    qualifier,
    "\\.?(\\s|$)", # leading: qualifier at the start
    "|",
    "(^|\\s)",
    qualifier,
    "\\.?$" # trailing: qualifier at the end
  )

  # single word, or a bare sp./spp./unid./indet. with nothing else of note --
  # expected to resolve at genus or higher, never species
  is_higher_rank <- !is_excluded &
    (word_count == 1 |
      stringr::str_detect(clean_name, qualifier_pattern))

  name_category <- dplyr::case_when(
    is_excluded ~ "excluded",
    is_higher_rank ~ "higher_rank_expected",
    TRUE ~ "full_name"
  )

  # strip the qualifier (leading or trailing) so GBIF gets just the bare
  # genus/family/order name
  strip_pattern <- stringr::str_c(
    "^",
    qualifier,
    "\\.?\\s*",
    "|",
    "\\s*",
    qualifier,
    "\\.?$"
  )
  query_name <- dplyr::if_else(
    name_category == "higher_rank_expected",
    stringr::str_squish(stringr::str_remove(clean_name, strip_pattern)),
    clean_name
  )
  query_name <- dplyr::if_else(
    name_category == "excluded",
    NA_character_,
    query_name
  )

  data.frame(
    raw_name = raw_name,
    clean_name = clean_name,
    query_name = query_name,
    name_category = name_category,
    stringsAsFactors = FALSE
  )
}
# ---- 2. Match against GBIF, with optional group filter ----------------------
taxa_match_gbif <- function(
  query_names,
  taxa_group = NULL,
  # bucket_size = 50,
  # sleep = 2,
  verbose = FALSE
) {
  name_data <- data.frame(
    scientificName = query_names,
    stringsAsFactors = FALSE
  )

  if (!is.null(taxa_group)) {
    name_data <- cbind(name_data, taxa_group_to_gbif_filter(taxa_group))
  }

  rgbif::name_backbone_checklist(
    name_data = name_data,
    verbose = verbose #,
    # bucket_size = bucket_size,
    # sleep = sleep
  )
}
# ---- 3. Resolve conflicting taxa_group assignments per unique name ----------
# Same raw name should always carry the same taxa_group -- if it doesn't,
# that's a data-entry problem worth flagging, not silently picking one.
taxa_resolve_group_conflicts <- function(names_vector, taxa_group_vector) {
  data.frame(
    raw_name = names_vector,
    taxa_group = taxa_group_vector,
    stringsAsFactors = FALSE
  ) |>
    dplyr::filter(!is.na(raw_name)) |>
    dplyr::distinct() |>
    dplyr::group_by(raw_name) |>
    dplyr::summarise(
      n_distinct_groups = dplyr::n_distinct(taxa_group),
      group_conflict = n_distinct_groups > 1,
      # if conflicting, don't guess -- fall back to unfiltered matching
      taxa_group = dplyr::if_else(
        group_conflict,
        NA_character_,
        dplyr::first(taxa_group)
      ),
      .groups = "drop"
    )
}
# ---- 4. Orchestrator: dedup -> classify -> match -> join back -> triage -----
taxa_build_gbif_crosswalk <- function(
  names_vector,
  taxa_group_vector
) {
  stopifnot(length(names_vector) == length(taxa_group_vector))

  unique_names <- taxa_resolve_group_conflicts(names_vector, taxa_group_vector)
  classified <- taxa_classify_name_string(unique_names$raw_name) |>
    dplyr::left_join(unique_names, by = "raw_name")

  queryable <- classified[classified$name_category != "excluded", ]
  excluded <- classified[classified$name_category == "excluded", ]

  match_results <- taxa_match_gbif(
    query_names = queryable$query_name,
    taxa_group = queryable$taxa_group
  )

  matched <- cbind(queryable, match_results) |>
    dplyr::mutate(
      is_synonym = stringr::str_detect(status, "SYNONYM"),
      final_usageKey = as.character(dplyr::if_else(
        is_synonym & !is.na(acceptedUsageKey),
        acceptedUsageKey,
        usageKey
      )),
      # the GBIF rank field that constrained this row's search (e.g. "class"
      # for a bird) -- NA for groups with no filter (fish, worm, protist, ...)
      coarsest_rank = taxa_group_to_gbif_rank_field(taxa_group),
      match_status = dplyr::case_when(
        group_conflict ~ "needs_review_group_conflict",
        is.na(usageKey) ~ "needs_manual_id",
        # a higher-rank-expected query (bare genus, "sp.", "unid.", ...) that
        # GBIF could only place at the group's own coarsest filter rank --
        # e.g. a "bird" entry that resolves to nothing finer than class Aves.
        # That's no more informative than taxa_group already told us, so send
        # it for manual review instead of auto-accepting it -- regardless of
        # whether GBIF called it EXACT, HIGHERRANK, etc.
        name_category == "higher_rank_expected" &
          !is.na(coarsest_rank) &
          !is.na(rank) &
          tolower(rank) == coarsest_rank ~ "needs_review_coarsest_group_only",
        matchType %in% c("EXACT", "VARIANT") ~ "matched",
        matchType == "FUZZY" &
          confidence > 90 ~ "matched_fuzzy_high_confidence",
        matchType == "FUZZY" ~ "needs_review_fuzzy",
        matchType == "HIGHERRANK" &
          name_category == "higher_rank_expected" ~ "matched",
        matchType == "HIGHERRANK" ~ "needs_review_rank_mismatch",
        TRUE ~ "needs_review_other"
      )
    )

  excluded <- excluded |>
    dplyr::mutate(
      final_usageKey = NA_character_,
      match_status = "excluded_manual_review"
    )

  dplyr::bind_rows(matched, excluded)
}

# ---- 5. Fetch a GBIF usage record directly ----------------------------------
# Used by taxa_apply_gbif_manual_matches() to turn a manually-entered
# usageKey into a canonical name + full hierarchy -- a manual match only ever
# comes with an ID, and (unlike an automated match) there's no
# name_backbone_checklist() response row to read a hierarchy from, so this is
# the one place in this script that still needs a live GBIF call per name.
# Always returns the same columns (NA-filled where GBIF doesn't have a value)
# so callers never have to guard for a missing column.
taxa_lookup_gbif_usage <- function(usage_keys) {
  hierarchy_cols <- c(
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species"
  )
  usage_keys <- unique(usage_keys[!is.na(usage_keys)])

  empty <- data.frame(
    usageKey = character(0),
    canonicalName = character(0),
    stringsAsFactors = FALSE
  )
  for (col in hierarchy_cols) {
    empty[[col]] <- character(0)
  }
  if (length(usage_keys) == 0) {
    return(empty)
  }

  records <- lapply(usage_keys, function(key) {
    usage <- tryCatch(rgbif::name_usage(key = key)$data, error = function(e) {
      NULL
    })
    row <- data.frame(
      usageKey = key,
      canonicalName = NA_character_,
      stringsAsFactors = FALSE
    )
    for (col in hierarchy_cols) {
      row[[col]] <- NA_character_
    }

    if (!is.null(usage) && nrow(usage) > 0) {
      if ("canonicalName" %in% names(usage)) {
        row$canonicalName <- usage$canonicalName[1]
      }
      for (col in hierarchy_cols) {
        if (col %in% names(usage)) row[[col]] <- usage[[col]][1]
      }
    }
    row
  })

  dplyr::bind_rows(records)
}

# ---- 6. Manual corrections: GBIF hop ----------------------------------------
# A frozen-registry CSV (3_gbif_manual_matches.csv), built FROM pipeline
# output rather than anticipated -- same pattern as
# aux_scientific_name_corrections.csv / aux_schema_metadata.csv elsewhere in
# this project, and the same pattern harmonize_names_to_checklist.R uses for
# its own (checklist-hop) registry.
#   taxa_export_gbif_review_template()  appends newly-flagged names to the CSV
#                                        (never overwrites an existing row, so
#                                        hand-entered matches are never
#                                        clobbered)
#   taxa_apply_gbif_manual_matches()    reads the CSV back in, overrides match
#                                        results for rows it covers, and
#                                        backfills their hierarchy automatically
#                                        via taxa_lookup_gbif_usage() (you
#                                        supply a usageKey, not a
#                                        classification)
# Workflow: build the crosswalk -> export the review template -> fill in the
# CSV by hand (a manual_gbif_usageKey of "NO_MATCH" marks "reviewed, confirmed
# there isn't one" so it stops being re-flagged) -> apply corrections. Both
# functions join on `raw_name`, the one identifier that's stable across the
# whole pipeline (unlike query_name, which can get stripped of a "sp."/"unid."
# qualifier). Downstream, harmonize_names_to_checklist.R expects to receive
# a crosswalk that has already been through this full cycle.

# "needs review" = anything taxa_build_gbif_crosswalk() didn't already accept
# outright (matched / matched_fuzzy_high_confidence) and isn't already covered
# by a prior manual entry in the CSV.
taxa_export_gbif_review_template <- function(gbif_crosswalk, path) {
  flagged <- gbif_crosswalk |>
    dplyr::filter(
      !match_status %in% c("matched", "matched_fuzzy_high_confidence", "manual")
    ) |>
    dplyr::distinct(raw_name, clean_name, name_category, match_status)

  existing <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  } else {
    data.frame(
      raw_name = character(0),
      clean_name = character(0),
      name_category = character(0),
      match_status = character(0),
      manual_gbif_usageKey = character(0),
      manual_gbif_canonicalName = character(0),
      notes = character(0),
      date_added = character(0),
      stringsAsFactors = FALSE
    )
  }

  new_rows <- dplyr::anti_join(flagged, existing, by = "raw_name")
  if (nrow(new_rows) == 0) {
    message("taxa_export_gbif_review_template(): no new names to flag.")
    return(invisible(existing))
  }

  new_rows$manual_gbif_usageKey <- NA_character_
  new_rows$manual_gbif_canonicalName <- NA_character_
  new_rows$notes <- NA_character_
  new_rows$date_added <- as.character(Sys.Date())

  updated <- dplyr::bind_rows(existing, new_rows)
  utils::write.csv(updated, path, row.names = FALSE, na = "")
  message(
    "taxa_export_gbif_review_template(): added ",
    nrow(new_rows),
    " name(s) to ",
    path,
    " -- fill in manual_gbif_usageKey (or \"NO_MATCH\") by hand."
  )
  invisible(updated)
}

# manual_gbif_usageKey == "NO_MATCH" is a sentinel: "a human looked, there
# isn't one" -- distinct from NA/blank ("not reviewed yet"), so confirmed
# non-matches stop being re-flagged by taxa_export_gbif_review_template().
taxa_apply_gbif_manual_matches <- function(gbif_crosswalk, path) {
  if (!file.exists(path)) {
    message(
      "taxa_apply_gbif_manual_matches(): ",
      path,
      " does not exist yet -- nothing applied."
    )
    return(gbif_crosswalk)
  }

  corrections <- utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    colClasses = "character"
  ) |>
    dplyr::filter(!is.na(manual_gbif_usageKey) & manual_gbif_usageKey != "")
  if (nrow(corrections) == 0) {
    return(gbif_crosswalk)
  }

  is_real_match <- corrections$manual_gbif_usageKey != "NO_MATCH"
  # usageKeys are alphanumeric now (GBIF's backbone no longer guarantees an
  # integer key), so these stay character all the way through -- no
  # as.integer() here.
  hierarchy <- taxa_lookup_gbif_usage(
    corrections$manual_gbif_usageKey[is_real_match]
  )
  hierarchy$usageKey <- as.character(hierarchy$usageKey)

  corrections <- corrections |>
    dplyr::left_join(hierarchy, by = c("manual_gbif_usageKey" = "usageKey"))

  gbif_crosswalk |>
    dplyr::left_join(
      corrections |>
        dplyr::select(
          raw_name,
          manual_gbif_usageKey,
          manual_gbif_canonicalName,
          kingdom,
          phylum,
          class,
          order,
          family,
          genus,
          species
        ),
      by = "raw_name",
      suffix = c("", "_manual")
    ) |>
    dplyr::mutate(
      is_no_match = manual_gbif_usageKey == "NO_MATCH",
      is_manual_match = !is.na(manual_gbif_usageKey) & !is_no_match,
      final_usageKey = dplyr::if_else(
        is_manual_match,
        manual_gbif_usageKey,
        final_usageKey
      ),
      canonicalName = dplyr::if_else(
        is_manual_match,
        manual_gbif_canonicalName,
        canonicalName
      ),
      kingdom = dplyr::if_else(is_manual_match, kingdom_manual, kingdom),
      phylum = dplyr::if_else(is_manual_match, phylum_manual, phylum),
      class = dplyr::if_else(is_manual_match, class_manual, class),
      order = dplyr::if_else(is_manual_match, order_manual, order),
      family = dplyr::if_else(is_manual_match, family_manual, family),
      genus = dplyr::if_else(is_manual_match, genus_manual, genus),
      species = dplyr::if_else(is_manual_match, species_manual, species),
      match_status = dplyr::case_when(
        is_no_match ~ "confirmed_no_match",
        is_manual_match ~ "manual",
        TRUE ~ match_status
      )
    ) |>
    dplyr::select(
      -manual_gbif_usageKey,
      -manual_gbif_canonicalName,
      -is_no_match,
      -is_manual_match,
      -kingdom_manual,
      -phylum_manual,
      -class_manual,
      -order_manual,
      -family_manual,
      -genus_manual,
      -species_manual
    )
}

# df = output from 2_harmonize_datasheet_versions.R

taxa1 <- df |>
  dplyr::select(taxa1_scientific, taxa1_group) |>
  rename(taxa_scientific = taxa1_scientific, taxa_group = taxa1_group) |>
  unique()
taxa2 <- df |>
  dplyr::select(taxa2_scientific, taxa2_group) |>
  rename(taxa_scientific = taxa2_scientific, taxa_group = taxa2_group) |>
  unique()

harmon <- rbind(taxa1, taxa2) |> unique()

crosswalk <- taxa_build_gbif_crosswalk(
  names_vector = harmon$taxa_scientific,
  taxa_group_vector = harmon$taxa_group
)

# flag anything that still needs a human -- appends only newly-flagged
# raw_names, so this is safe to re-run:
taxa_export_gbif_review_template(
  crosswalk,
  "./R/L0/3_gbif_manual_matches.csv"
)

# ... fill in aux_gbif_manual_matches.csv by hand (manual_gbif_usageKey
# column; "NO_MATCH" means "reviewed, confirmed there isn't one"), then
# re-run with corrections applied:
crosswalk <- taxa_apply_gbif_manual_matches(
  crosswalk,
  "./R/L0/3_gbif_manual_matches.csv"
)

write.csv(crosswalk, "./R/L0/3_metanetwork_gbif_crosswalk.csv", row.names = F)

# taxa_count_avilist_matches <- function(crosswalk, avilist_2025) {
#   avilist_combined <-
#     avilist_2025 |>
#     dplyr::mutate(dplyr::across(dplyr::everything(), as.character)) |>
#     tidyr::unite(
#       "all_cols",
#       dplyr::everything(),
#       sep = " ",
#       remove = TRUE,
#       na.rm = TRUE
#     ) |>
#     dplyr::pull(all_cols)

#   crosswalk |>
#     dplyr::mutate(
#       n_avilist_rows = purrr::map_int(
#         query_name,
#         ~ sum(stringr::str_detect(avilist_combined, stringr::fixed(.x)))
#       )
#     )
# }

# avilist_2025 <- avilistr::avilist_2025

# crosswalk_new <- taxa_count_avilist_matches(crosswalk_new, avilist_2025)
