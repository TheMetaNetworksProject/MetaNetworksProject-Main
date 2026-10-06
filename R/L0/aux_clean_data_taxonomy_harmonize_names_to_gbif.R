# TITLE:            aux_clean_data_taxonomy_harmonize_names_to_gbif.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:
# DATA INPUT:       None directly -- this script only DEFINES functions.
#                   They are called from 3_clean_data.R by
#                   harmonize_taxonomy_gbif(), which passes in the cleaned
#                   data frame's taxa1_scientific/taxa1_group and
#                   taxa2_scientific/taxa2_group columns, plus the path to
#                   aux_clean_data_taxonomy_gbif_manual_matches.csv (the
#                   manual-correction CSV, created by
#                   taxa_export_gbif_review_template(), edited by hand,
#                   re-read on the next run).
# DATA OUTPUT:      None directly. The functions produce `crosswalk`: one row
#                   per unique MetaNetworks raw_name, matched against the
#                   GBIF backbone with a match_status, final_usageKey, and
#                   accepted taxonomy (every GBIF rank). 3aux_clean_data_taxonomy.R writes it to
#                   aux_clean_data_taxonomy_metanetwork_gbif_crosswalk.csv.
# DATE:             initiated: unknown -- predates this header, please
#                   backfill from version control if available; last
#                   updated: 6 October 2026.
# OVERVIEW:         Classifies each raw MetaNetworks taxon name (full name /
#                   higher-rank-expected / excluded), matches it against the
#                   GBIF backbone -- optionally constrained by taxa_group
#                   (e.g. bird names searched within class Aves) -- and
#                   triages the result into an automatic match or a row
#                   needing manual review. Supports a hand-edited
#                   manual-match correction registry
#                   (aux_clean_data_taxonomy_gbif_manual_matches.csv) that
#                   overrides an automated match by usageKey and backfills
#                   its accepted taxonomy via a live GBIF lookup.
# REQUIRES:         rgbif, tidyverse. avilistr, for the commented-out
#                   exploratory AviList match-count helper at the bottom.
#                   Sourced by 3_clean_data.R. harmonize_names_to_checklist.R
#                   consumes the resulting crosswalk downstream, and expects
#                   it to already be fully reviewed and corrected (i.e. the
#                   whole build -> export -> hand-fill -> apply cycle).
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
#                   2026-10-06: converted to a functions-only script. The run
#                   block that used to sit at the bottom (build -> export ->
#                   apply -> write.csv on the full `df`) moved into
#                   harmonize_taxonomy_gbif() in
#                   3aux_clean_data_taxonomy.R, which only queries GBIF for
#                   names not already in the saved crosswalk (or rebuilds
#                   everything when new_crosswalk = TRUE).
#                   Sourcing this file no longer runs any GBIF queries.
#                   taxa_build_gbif_crosswalk() now skips the GBIF call when
#                   every name passed in is "excluded" (cf./aff./
#                   morphospecies), which can happen in an incremental run
#                   with only a handful of new names.
#                   2026-10-06: accepted taxonomy rebuilt from the accepted
#                   usageKey. The match columns (usageKey, rank,
#                   canonicalName) still describe the matched name; new
#                   final_rank / final_canonicalName plus every rank column
#                   (kingdom ... species, subspecies, tribe, ...) and its
#                   <rank>Key describe the ACCEPTED taxon. Synonyms and manual
#                   matches get every rank column wiped and refilled from the
#                   accepted record (taxa_resolve_accepted_taxonomy(),
#                   taxa_overwrite_taxonomy()).
#                   2026-10-06: taxa_lookup_gbif_usage() now uses
#                   name_backbone_checklist() (GBIF v2 match API) with a
#                   usageKey column instead of rgbif::name_usage(). name_usage()
#                   hits the v1 API, which doesn't know the new alphanumeric
#                   keys, so every lookup had been silently returning nothing
#                   (manual matches had no taxonomy). A manual key GBIF doesn't
#                   recognize now gets match_status "manual_key_not_found".
#                   manual_gbif_canonicalName is a note for humans only -- the
#                   accepted name always comes from GBIF.

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

  excluded <- excluded |>
    dplyr::mutate(
      final_usageKey = NA_character_,
      match_status = "excluded_manual_review"
    )

  # nothing to send to GBIF (e.g. an incremental run where every new name is
  # cf./aff./a morphospecies code) -- name_backbone_checklist() can't take an
  # empty query, so return the excluded rows on their own
  if (nrow(queryable) == 0) {
    return(excluded)
  }

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

  dplyr::bind_rows(matched, excluded)
}

# ---- 5. Look up the ACCEPTED GBIF record for a usage key --------------------
# Usage keys in this crosswalk come from GBIF's v2 match API (the new,
# alphanumeric keys), so lookups go through the same API:
# name_backbone_checklist() with a usageKey column. (rgbif::name_usage() uses
# the old v1 API, which only knows the old numeric backbone keys -- it fails
# on these keys, which is why manual matches used to come back with no
# taxonomy.)
#
# rgbif returns each rank in a record's classification as its own column,
# named by the lowercased rank ("kingdom", "species", "subspecies", "tribe",
# ...), plus a matching "<rank>Key" column. taxa_gbif_rank_cols() picks those
# out by that pairing, so every rank GBIF returns is kept, not a fixed list.
taxa_gbif_rank_cols <- function(col_names) {
  col_names[paste0(col_names, "Key") %in% col_names]
}

# One batched lookup per call. If a key is a synonym, its acceptedUsageKey is
# looked up in a second batch, so everything returned describes the ACCEPTED
# taxon. Returns one row per input key:
#   usageKey           the key passed in (join on this)
#   accepted_usageKey  the accepted taxon's key (= usageKey if already
#                      accepted; NA if the key wasn't found)
#   canonicalName, rank, and every rank column + "<rank>Key" column of the
#   accepted taxon (NA where the lookup failed)
taxa_lookup_gbif_usage <- function(usage_keys) {
  usage_keys <- unique(as.character(
    usage_keys[!is.na(usage_keys) & usage_keys != ""]
  ))
  out <- data.frame(usageKey = usage_keys, stringsAsFactors = FALSE)
  if (length(usage_keys) == 0) {
    out$accepted_usageKey <- character(0)
    out$canonicalName <- character(0)
    out$rank <- character(0)
    return(out)
  }

  fetch_by_key <- function(keys) {
    # scientificName is an all-NA dummy column: with a ONE-column data frame
    # rgbif assumes that column is scientificName and renames it. NA values
    # are dropped from the query, so only usageKey is sent.
    res <- rgbif::name_backbone_checklist(
      name_data = data.frame(
        scientificName = NA_character_,
        usageKey = keys,
        stringsAsFactors = FALSE
      )
    )
    res <- dplyr::mutate(res, dplyr::across(dplyr::everything(), as.character))
    if (!"usageKey" %in% names(res)) {
      res$usageKey <- NA_character_
    }
    if (!"acceptedUsageKey" %in% names(res)) {
      res$acceptedUsageKey <- NA_character_
    }
    # a key GBIF doesn't recognize comes back with no usageKey -- drop it
    res[!is.na(res$usageKey), ]
  }

  first <- fetch_by_key(usage_keys)
  m <- match(usage_keys, first$usageKey)
  out$accepted_usageKey <- dplyr::coalesce(
    first$acceptedUsageKey[m],
    first$usageKey[m]
  )

  # synonyms: fetch the accepted record itself (the synonym's record has the
  # synonym's name and rank)
  synonym_targets <- unique(stats::na.omit(first$acceptedUsageKey))
  records <- first[is.na(first$acceptedUsageKey), ]
  if (length(synonym_targets) > 0) {
    records <- dplyr::bind_rows(records, fetch_by_key(synonym_targets))
  }
  records <- records[!duplicated(records$usageKey), ]

  rank_cols <- taxa_gbif_rank_cols(names(records))
  keep <- c(
    "usageKey",
    "canonicalName",
    "rank",
    rank_cols,
    paste0(rank_cols, "Key")
  )
  keep <- intersect(keep, names(records))
  records <- records[, keep, drop = FALSE]
  names(records)[names(records) == "usageKey"] <- "accepted_usageKey"

  dplyr::left_join(out, records, by = "accepted_usageKey")
}

# Replace the accepted taxonomy for crosswalk rows `rows` with the lookup
# results in `accepted` (from taxa_lookup_gbif_usage()), matched by
# `lookup_keys` (one key per row in `rows`). EVERY rank column (and its Key)
# in those rows is wiped first, so nothing from the matched name's
# classification survives -- e.g. a synonym's leftover subspecies column.
# Sets final_usageKey (accepted key), final_rank and final_canonicalName.
# A failed lookup leaves final_rank NA.
taxa_overwrite_taxonomy <- function(
  gbif_crosswalk,
  rows,
  lookup_keys,
  accepted
) {
  if (length(rows) == 0) {
    return(gbif_crosswalk)
  }
  m <- match(lookup_keys, accepted$usageKey)

  old_rank_cols <- taxa_gbif_rank_cols(names(gbif_crosswalk))
  for (col in c(old_rank_cols, paste0(old_rank_cols, "Key"))) {
    gbif_crosswalk[[col]][rows] <- NA_character_
  }

  new_rank_cols <- taxa_gbif_rank_cols(names(accepted))
  for (col in c(new_rank_cols, paste0(new_rank_cols, "Key"))) {
    if (!col %in% names(gbif_crosswalk)) {
      gbif_crosswalk[[col]] <- NA_character_
    }
    gbif_crosswalk[[col]][rows] <- accepted[[col]][m]
  }

  gbif_crosswalk$final_usageKey[rows] <- dplyr::coalesce(
    accepted$accepted_usageKey[m],
    gbif_crosswalk$final_usageKey[rows]
  )
  gbif_crosswalk$final_rank[rows] <- accepted$rank[m]
  gbif_crosswalk$final_canonicalName[rows] <- accepted$canonicalName[m]
  gbif_crosswalk
}

# ---- 6. Manual corrections: GBIF hop ----------------------------------------
# A frozen-registry CSV (aux_clean_data_taxonomy_gbif_manual_matches.csv),
# built FROM pipeline output rather than anticipated -- same pattern as
# aux_scientific_name_corrections.csv / aux_schema_metadata.csv elsewhere in
# this project, and the same pattern harmonize_names_to_checklist.R uses for
# its own (checklist-hop) registry.
#   taxa_export_gbif_review_template()  appends newly-flagged names to the CSV
#                                        (never overwrites an existing row, so
#                                        hand-entered matches are never
#                                        clobbered)
#   taxa_apply_gbif_manual_matches()    reads the CSV back in, overrides match
#                                        results for rows it covers, and
#                                        rebuilds their accepted taxonomy
#                                        automatically via
#                                        taxa_lookup_gbif_usage() (you supply
#                                        a usageKey, not a classification)
# Workflow: build the crosswalk -> export the review template -> fill in the
# CSV by hand (a manual_gbif_usageKey of "NO_MATCH" marks "reviewed, confirmed
# there isn't one" so it stops being re-flagged) -> apply corrections. Both
# functions join on `raw_name`, the one identifier that's stable across the
# whole pipeline (unlike query_name, which can get stripped of a "sp."/"unid."
# qualifier). harmonize_taxonomy_gbif() in 3_clean_data.R runs this whole
# cycle. Downstream, harmonize_names_to_checklist.R expects to receive a
# crosswalk that has already been through it.

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
  # only names that are in this crosswalk
  corrections <- corrections[
    corrections$raw_name %in% gbif_crosswalk$raw_name,
  ]
  if (nrow(corrections) == 0) {
    return(gbif_crosswalk)
  }

  for (col in c("final_rank", "final_canonicalName")) {
    if (!col %in% names(gbif_crosswalk)) {
      gbif_crosswalk[[col]] <- NA_character_
    }
  }

  rows <- match(corrections$raw_name, gbif_crosswalk$raw_name)
  is_no_match <- corrections$manual_gbif_usageKey == "NO_MATCH"

  # NO_MATCH: reviewed, confirmed there isn't one
  gbif_crosswalk$match_status[rows[is_no_match]] <- "confirmed_no_match"

  # real matches: rebuild the accepted taxonomy from the manual key. usageKey,
  # rank and canonicalName (the automated match) are left as they were; the
  # manual key, and manual_gbif_canonicalName (a note for humans only), live
  # in the CSV. Keys stay character -- they're alphanumeric.
  manual_rows <- rows[!is_no_match]
  manual_keys <- corrections$manual_gbif_usageKey[!is_no_match]
  if (length(manual_rows) > 0) {
    accepted <- taxa_lookup_gbif_usage(manual_keys)
    gbif_crosswalk$final_usageKey[manual_rows] <- manual_keys
    gbif_crosswalk <- taxa_overwrite_taxonomy(
      gbif_crosswalk,
      rows = manual_rows,
      lookup_keys = manual_keys,
      accepted = accepted
    )

    # a key GBIF doesn't recognize gets its own status, so it shows up as an
    # error in check_taxa_gbif() instead of passing as "manual"
    found <- !is.na(gbif_crosswalk$final_rank[manual_rows])
    gbif_crosswalk$match_status[manual_rows] <- ifelse(
      found,
      "manual",
      "manual_key_not_found"
    )
    if (any(!found)) {
      warning(
        "taxa_apply_gbif_manual_matches(): ",
        sum(!found),
        " manual usageKey(s) not found in GBIF: ",
        paste(unique(manual_keys[!found]), collapse = ", ")
      )
    }
  }

  gbif_crosswalk
}

# ---- 7. Accepted taxonomy for every automated crosswalk row -----------------
# The match columns (usageKey, rank, canonicalName) describe the name GBIF
# MATCHED, which for a synonym is the synonym itself. These columns describe
# the ACCEPTED taxon:
#   final_usageKey, final_rank, final_canonicalName, and every rank column
#   (kingdom ... species, subspecies, tribe, ...) with its <rank>Key column
# Filled per row:
#   - manual / manual_key_not_found / confirmed_no_match: handled by
#     taxa_apply_gbif_manual_matches(), skipped here
#   - automated synonym: rebuilt entirely from the accepted key's GBIF record
#     (taxa_lookup_gbif_usage() + taxa_overwrite_taxonomy()) -- every rank
#     column is wiped and refilled
#   - automated accepted match: the match response already describes the
#     accepted taxon, so final_rank = rank and final_canonicalName =
#     canonicalName (no GBIF call)
# Cached: only rows with no final_rank yet are filled, so after the first run
# only new names cost GBIF calls (or everything when new_crosswalk = TRUE). A
# failed lookup leaves final_rank NA and is retried next run.
taxa_resolve_accepted_taxonomy <- function(gbif_crosswalk) {
  needed <- c(
    "canonicalName",
    "rank",
    "is_synonym",
    "final_rank",
    "final_canonicalName"
  )
  for (col in needed) {
    if (!col %in% names(gbif_crosswalk)) {
      gbif_crosswalk[[col]] <- NA_character_
    }
  }

  handled_by_manual <- gbif_crosswalk$match_status %in%
    c("manual", "manual_key_not_found", "confirmed_no_match")
  is_synonym <- gbif_crosswalk$is_synonym %in% "TRUE"
  to_fill <- !handled_by_manual &
    !is.na(gbif_crosswalk$final_usageKey) &
    is.na(gbif_crosswalk$final_rank)

  # accepted match: copy from the match response
  rows <- which(to_fill & !is_synonym)
  gbif_crosswalk$final_rank[rows] <- gbif_crosswalk$rank[rows]
  gbif_crosswalk$final_canonicalName[rows] <- gbif_crosswalk$canonicalName[rows]

  # synonym: rebuild from the accepted key's record
  rows <- which(to_fill & is_synonym)
  if (length(rows) > 0) {
    message(
      "taxa_resolve_accepted_taxonomy(): fetching accepted taxonomy for ",
      length(rows),
      " synonym(s)."
    )
    keys <- gbif_crosswalk$final_usageKey[rows]
    gbif_crosswalk <- taxa_overwrite_taxonomy(
      gbif_crosswalk,
      rows = rows,
      lookup_keys = keys,
      accepted = taxa_lookup_gbif_usage(keys)
    )

    n_failed <- sum(is.na(gbif_crosswalk$final_rank[rows]))
    if (n_failed > 0) {
      warning(
        "taxa_resolve_accepted_taxonomy(): ",
        n_failed,
        " accepted-taxonomy lookup(s) failed -- left NA for those rows ",
        "(retried on the next run)."
      )
    }
  }

  gbif_crosswalk
}

# ---- 8. (exploratory) AviList match counts ----------------------------------
# Not part of the pipeline -- kept for reference.

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
