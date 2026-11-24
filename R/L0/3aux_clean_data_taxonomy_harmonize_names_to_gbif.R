# TITLE:            3aux_clean_data_taxonomy_harmonize_names_to_gbif.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar, Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas,
#                   Minyoung Lee, Patrick Bills
# DATA INPUT:       Two CSVs, both read by taxa_update_gbif_crosswalk() from
#                   paths its caller passes in (no path is read from the
#                   enclosing environment):
#                     ./docs/master_metanetworks_gbif_crosswalk.csv
#                     3aux_clean_data_taxonomy_gbif_manual_matches.csv
#                   The manual-matches CSV is created by
#                   taxa_export_gbif_review_template(), edited by hand, and
#                   re-read on the next run.
# DATA OUTPUT:      Both CSVs above are written back by
#                   taxa_update_gbif_crosswalk():
#                     - crosswalk: one row per unique MetaNetworks raw_name,
#                       matched against the GBIF backbone, with a
#                       match_status, final_usageKey, and the accepted
#                       taxonomy (every GBIF rank GBIF returns)
#                     - manual matches: newly flagged names appended, never
#                       overwritten
#                   taxa_update_gbif_crosswalk() also RETURNS the updated
#                   crosswalk to its caller (3a_aux_clean_data_taxonomy.R).
# DATE:             initiated: summer 2026; last updated November 2026
# OVERVIEW:         The GBIF layer of the taxonomy step. Everything here
#                   operates on either (a) a vector of raw names plus a
#                   matching vector of taxa_groups, or (b) a crosswalk data
#                   frame. Nothing here knows the MetaNetworks data frame
#                   schema (taxa1_scientific, taxa2_group, ...) or the
#                   clean_data() note/flagging contract -- that lives in
#                   3a_aux_clean_data_taxonomy.R. Keeping that boundary is
#                   the point of the split: this file owns GBIF and the
#                   crosswalk, that file owns rows and columns.
#
#                   What it does:
#                     1. Classifies each raw taxon name (full name /
#                        higher-rank-expected / excluded).
#                     2. Matches it against the GBIF backbone, optionally
#                        constrained by taxa_group (e.g. bird names searched
#                        within class Aves).
#                     3. Triages the result into an automatic match or a row
#                        needing manual review.
#                     4. Supports a hand-edited manual-match correction
#                        registry
#                        (3aux_clean_data_taxonomy_gbif_manual_matches.csv)
#                        that overrides an automated match by usageKey and
#                        backfills its accepted taxonomy via a live GBIF
#                        lookup.
#                     5. Resolves accepted taxonomy for automated rows.
#                     6. Exposes the crosswalk to callers through accessors
#                        (section 8) so that no other script has to know
#                        which crosswalk columns exist or which match_status
#                        values count as resolved.
#                     7. Owns reading and writing the crosswalk CSV and the
#                        manual-matches CSV (section 9), so both files in the
#                        frozen-registry pattern have a single owner.
# NOTES:            Every call is namespace-qualified (rgbif::, dplyr::,
#                   stringr::, stats::, utils::) and the native pipe needs no
#                   package, so this file deliberately attaches nothing --
#                   sourcing it no longer changes the caller's search path.
#                   Scripts that rely on tidyverse being attached must call
#                   library() themselves (3_clean_data.R).
#                   Sections 5, 7 and 9 make live GBIF calls, so they need a
#                   network connection; a GBIF outage will stop clean_data().
# NOTE:             Original version of this code was manually created, but was refactored and
#                   comments were added using AI. All code was human-reviewed after refactoring.

# ---- 0. taxa_group -> GBIF classification filter -----------------------------

# Which GBIF rank field constrains a group's search.
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

  # rgbif drops columns that are empty for the whole batch (e.g.
  # acceptedUsageKey when no name is a synonym). Add them back as NA so the
  # mutate() below always finds them.
  expected_cols <- c(
    "usageKey",
    "acceptedUsageKey",
    "status",
    "rank",
    "canonicalName",
    "matchType",
    "confidence"
  )
  for (col in setdiff(expected_cols, names(match_results))) {
    match_results[[col]] <- NA
  }

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
      # NOTE: any status added here must also be classified in
      # taxa_resolved_statuses() (section 8) -- that function is the single
      # definition of which statuses count as resolved downstream.
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
# on these keys.)
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
# A frozen-registry CSV (3aux_clean_data_taxonomy_gbif_manual_matches.csv)
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
# qualifier). taxa_update_gbif_crosswalk() (section 9) runs this whole cycle.
# Downstream, harmonize_names_to_checklist.R expects to receive a crosswalk
# that has already been through it.

# "needs review" = anything taxa_build_gbif_crosswalk() didn't already accept
# outright (see taxa_resolved_statuses(), section 8) and isn't already covered
# by a prior manual entry in the CSV.
#
# This is a status-only test on purpose: it runs BEFORE
# taxa_resolve_accepted_taxonomy() has filled final_rank, so it must not use
# taxa_is_resolved(), which also requires final_rank.
taxa_export_gbif_review_template <- function(gbif_crosswalk, path) {
  flagged <- gbif_crosswalk |>
    dplyr::filter(!match_status %in% taxa_resolved_statuses()) |>
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

# ---- 8. Crosswalk accessors -------------------------------------------------
# Everything a caller needs to know about a crosswalk row, without the caller
# touching a crosswalk column name or hard-coding a match_status value. These
# are the only functions 3a_aux_clean_data_taxonomy.R should need to read the
# crosswalk with.

# THE single definition of which match_status values count as resolved.
# Used by taxa_export_gbif_review_template() (section 6, what NOT to flag for
# review), taxa_is_resolved() below, and, through those, by the cleaner in
# 3a_aux_clean_data_taxonomy.R. Add a status to the case_when() in
# taxa_build_gbif_crosswalk() and this is the one place to decide whether it
# passes.
taxa_resolved_statuses <- function() {
  c("matched", "matched_fuzzy_high_confidence", "manual")
}

# Resolved = a trusted match status AND an accepted taxon actually looked up.
# A resolved status with a failed accepted-taxonomy lookup (final_rank NA) is
# NOT resolved -- taxa_match_status_label() gives it its own label.
# Requires final_rank/final_usageKey, so only call this on a crosswalk that
# has been through taxa_resolve_accepted_taxonomy().
taxa_is_resolved <- function(gbif_crosswalk) {
  gbif_crosswalk$match_status %in%
    taxa_resolved_statuses() &
    !is.na(gbif_crosswalk$final_usageKey) &
    !is.na(gbif_crosswalk$final_rank)
}

# match_status, except that a resolved status whose accepted-taxonomy lookup
# failed gets a label that says so (it's a transient GBIF failure, not a name
# problem, and it's retried on the next run).
taxa_match_status_label <- function(gbif_crosswalk) {
  label <- gbif_crosswalk$match_status
  lookup_failed <- gbif_crosswalk$match_status %in%
    taxa_resolved_statuses() &
    is.na(gbif_crosswalk$final_rank)
  label[lookup_failed] <- "accepted taxonomy lookup failed, retried next run"
  label
}

# The accepted GBIF name for each crosswalk row = the value of the column
# named for its accepted rank (final_rank SUBSPECIES -> the `subspecies`
# column). If that column is missing or blank (e.g. a rank GBIF reports
# without a classification column), fall back to final_canonicalName.
# Returns one name per crosswalk row.
taxa_accepted_name <- function(gbif_crosswalk) {
  rank_col <- tolower(gbif_crosswalk$final_rank)

  from_rank <- vapply(
    seq_len(nrow(gbif_crosswalk)),
    function(i) {
      if (!is.na(rank_col[i]) && rank_col[i] %in% names(gbif_crosswalk)) {
        as.character(gbif_crosswalk[[rank_col[i]]][i])
      } else {
        NA_character_
      }
    },
    character(1)
  )

  # treat "" as missing so the fallback actually fires (a blank rank column
  # read back from CSV is "", not NA)
  blank_to_na <- function(x) {
    x[!is.na(x) & x == ""] <- NA_character_
    x
  }

  dplyr::coalesce(
    blank_to_na(from_rank),
    blank_to_na(gbif_crosswalk$final_canonicalName)
  )
}

# Look up a vector of raw taxon names in the crosswalk. Returns ONE ROW PER
# INPUT NAME, in input order, so a caller can drop the columns straight onto
# its own data frame:
#   raw_name       the name passed in
#   resolved       TRUE if this name has a usable accepted GBIF taxon
#   match_status   taxa_match_status_label(), or "not in crosswalk"
#   gbif_name      accepted GBIF name   (NA unless resolved)
#   gbif_rank      accepted GBIF rank   (NA unless resolved)
#   gbif_usageKey  accepted usageKey    (NA unless resolved)
# An NA input name comes back resolved = FALSE, match_status =
# "not in crosswalk"; the caller decides what to do with blanks.
taxa_crosswalk_lookup <- function(gbif_crosswalk, taxon_names) {
  idx <- match(taxon_names, gbif_crosswalk$raw_name) # NA = not in crosswalk

  resolved <- taxa_is_resolved(gbif_crosswalk)[idx]
  resolved[is.na(resolved)] <- FALSE

  status <- taxa_match_status_label(gbif_crosswalk)[idx]
  status[is.na(status)] <- "not in crosswalk"

  data.frame(
    raw_name = taxon_names,
    resolved = resolved,
    match_status = status,
    gbif_name = dplyr::if_else(
      resolved,
      taxa_accepted_name(gbif_crosswalk)[idx],
      NA_character_
    ),
    gbif_rank = dplyr::if_else(
      resolved,
      gbif_crosswalk$final_rank[idx],
      NA_character_
    ),
    gbif_usageKey = dplyr::if_else(
      resolved,
      gbif_crosswalk$final_usageKey[idx],
      NA_character_
    ),
    stringsAsFactors = FALSE
  )
}

# ---- 9. Update (or rebuild) the saved crosswalk -----------------------------

#' Update (or rebuild) the GBIF taxonomy crosswalk for a set of taxon names
#'
#' Takes a data frame of (raw_name, taxa_group) pairs -- NOT the MetaNetworks
#' data frame; extracting the pairs from taxa1_*/taxa2_* columns is the
#' caller's job -- and compares the names against the `raw_name` column of
#' the saved crosswalk.
#'   new_crosswalk = FALSE (default): only names NOT already in the saved
#'     crosswalk are sent to GBIF (via taxa_build_gbif_crosswalk()), and their
#'     rows are appended to it. If there are no new names, GBIF matching is
#'     skipped. If no crosswalk file exists yet, a full one is built.
#'   new_crosswalk = TRUE: the saved crosswalk is ignored and every name is
#'     re-queried against GBIF from scratch; the result overwrites the file.
#'
#' Either way, the crosswalk then goes through the manual-match cycle:
#' newly flagged names are appended to the manual-matches CSV (hand-entered
#' rows are never overwritten) and every filled-in manual match is applied.
#' That runs even when there are no new names, so usageKeys you've filled in
#' by hand since the last run are picked up. The manual-matches CSV is never
#' reset, including when new_crosswalk = TRUE.
#'
#' Names are matched on the exact `raw_name` string. A name already in the
#' crosswalk is never re-queried in incremental mode, even if its taxa_group
#' has changed -- use new_crosswalk = TRUE for that.
#'
#' Every column is stored as character (GBIF usageKeys are alphanumeric, and
#' it keeps saved and newly queried rows the same type when combined).
#' @param taxa data frame with raw_name and taxa_group columns. Rows with an
#'   NA raw_name are dropped and the pairs are deduplicated here, so callers
#'   can just stack their name columns. Pairs, not bare names, so that
#'   taxa_resolve_group_conflicts() can still catch a new name entered under
#'   two different groups.
#' @param crosswalk_path path to the crosswalk CSV (read if it exists, always
#'   written)
#' @param manual_matches_path path to the manual GBIF matches CSV (created
#'   if it doesn't exist)
#' @param new_crosswalk TRUE = rebuild the whole crosswalk from fresh GBIF
#'   queries; FALSE = only query names not already in the crosswalk
#' @returns the updated crosswalk (also written to crosswalk_path), with
#'   final_rank, final_canonicalName and final_usageKey filled in. Read it
#'   with the section 8 accessors.
taxa_update_gbif_crosswalk <- function(
  taxa,
  crosswalk_path,
  manual_matches_path,
  new_crosswalk = FALSE
) {
  stopifnot(all(c("raw_name", "taxa_group") %in% names(taxa)))

  taxa <- unique(taxa[!is.na(taxa$raw_name), c("raw_name", "taxa_group")])

  # decide which names to query
  if (new_crosswalk) {
    message(
      "taxa_update_gbif_crosswalk(): new_crosswalk = TRUE -- re-querying ",
      "all names against GBIF."
    )
    existing <- NULL
    to_query <- taxa
  } else if (!file.exists(crosswalk_path)) {
    message(
      "taxa_update_gbif_crosswalk(): no crosswalk at ",
      crosswalk_path,
      " -- building one from scratch."
    )
    existing <- NULL
    to_query <- taxa
  } else {
    existing <- utils::read.csv(
      crosswalk_path,
      stringsAsFactors = FALSE,
      colClasses = "character"
    )
    to_query <- taxa[!taxa$raw_name %in% existing$raw_name, ]
  }

  n_new <- length(unique(to_query$raw_name))

  # query GBIF for the new names only, then append them
  if (n_new == 0) {
    message(
      "taxa_update_gbif_crosswalk(): no new names -- skipping GBIF matching."
    )
    crosswalk <- existing
  } else {
    message(
      "taxa_update_gbif_crosswalk(): querying GBIF for ",
      n_new,
      " name(s)."
    )
    new_rows <- taxa_build_gbif_crosswalk(
      names_vector = to_query$raw_name,
      taxa_group_vector = to_query$taxa_group
    ) |>
      dplyr::mutate(dplyr::across(dplyr::everything(), as.character))

    # bind_rows() fills columns missing from either side with NA (rgbif
    # doesn't always return the same set of columns)
    crosswalk <- dplyr::bind_rows(existing, new_rows)
  }

  # manual-match cycle: flag anything new that needs a human, then apply
  # every manual match filled in so far
  taxa_export_gbif_review_template(crosswalk, manual_matches_path)
  crosswalk <- taxa_apply_gbif_manual_matches(crosswalk, manual_matches_path)

  # accepted taxonomy (final_rank, final_canonicalName, every rank column)
  # for automated rows. Cached in the saved crosswalk via final_rank, so only
  # rows that don't have it yet -- new synonyms -- trigger a GBIF lookup.
  crosswalk <- taxa_resolve_accepted_taxonomy(crosswalk)

  utils::write.csv(crosswalk, crosswalk_path, row.names = FALSE)
  message(
    "taxa_update_gbif_crosswalk(): wrote ",
    nrow(crosswalk),
    " row(s) to ",
    crosswalk_path
  )

  crosswalk
}
