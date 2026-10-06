# TITLE:            3aux_clean_data_taxonomy.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:
# DATA INPUT:       Called from clean_data() in 3_clean_data.R on the data
#                   frame after text cleaning (so taxon names are already
#                   standardized and typo-corrected). Reads/writes:
#                   aux_clean_data_taxonomy_metanetwork_gbif_crosswalk.csv
#                   and aux_clean_data_taxonomy_gbif_manual_matches.csv.
# DATA OUTPUT:      df with six new columns -- tx1_gbif, tx1_gbif_rank,
#                   tx1_gbif_usageKey and the same for tx2 (accepted GBIF
#                   name, its rank, and its usageKey for taxa1_scientific /
#                   taxa2_scientific) -- and an error appended for every name
#                   that doesn't resolve.
#                   Updates the crosswalk CSV (new names appended) and the
#                   manual-matches CSV (newly flagged names appended).
# DATE:             initiated: 6 October 2026
# OVERVIEW:         Taxonomy step of clean_data(). For the taxa1/taxa2 names:
#                     1. harmonize_taxonomy_gbif(): any name not already in
#                        the crosswalk is queried against GBIF and appended;
#                        newly flagged names go into the manual-matches CSV;
#                        every filled-in manual match is applied.
#                     2. check_taxa_gbif(): each row's names are looked up in
#                        the updated crosswalk. Resolved names fill
#                        tx1_gbif / tx2_gbif with the value of the accepted
#                        taxon's rank column (e.g. final_rank GENUS -> the
#                        `genus` column). Unresolved names get an error
#                        (so the source file is flagged) telling you to fix
#                        the typo or fill in a manual usageKey.
#                   "Resolved" = match_status of matched,
#                   matched_fuzzy_high_confidence, or manual. Every other
#                   status (needs_manual_id, needs_review_*,
#                   excluded_manual_review, manual_key_not_found) is an
#                   error, and so is a resolved status whose accepted
#                   taxonomy lookup failed (final_rank blank).
#                   A name marked NO_MATCH in the manual-matches CSV
#                   (confirmed_no_match) is also an error: interactions with
#                   a taxon that has no GBIF match are not allowed in the
#                   dataset. Following this script's contract (never drop
#                   rows), the row is not removed here -- the error flags the
#                   file, move_flagged_files() drops all of its rows, and the
#                   fix is to delete that interaction from the source file.
#                   The file stays flagged on every run until that's done.
# REQUIRES:         aux_clean_data_taxonomy_harmonize_names_to_gbif.R
#                   (sourced first, for taxa_build_gbif_crosswalk(),
#                   taxa_export_gbif_review_template(),
#                   taxa_apply_gbif_manual_matches(),
#                   taxa_resolve_accepted_taxonomy()).
#                   3aux_clean_data_basic_formatting.R, for add_note().
# NOTES:            Makes live GBIF calls (new names + one lookup per manual
#                   match) and writes two CSVs, so it needs a network
#                   connection and a GBIF outage will stop clean_data().
#                   Because it runs inside clean_data(), names from files
#                   that end up flagged for other reasons are still queried
#                   and added to the crosswalk. A typo that is later fixed
#                   in its source file leaves a harmless stale row in the
#                   crosswalk. Its row in the manual-matches CSV should be
#                   deleted by hand (the error message says so), so the
#                   registry only holds names that are really in the data.

# ============================================================================
# UPDATE (OR REBUILD) THE CROSSWALK
# ============================================================================

#' Update (or rebuild) the GBIF taxonomy crosswalk for the names in df
#'
#' Collects every (name, taxa_group) pair from the taxa1_* and taxa2_*
#' columns and compares the names against the `raw_name` column of the saved
#' crosswalk.
#'   new_crosswalk = FALSE (default): only names NOT already in the saved
#'     crosswalk are sent to GBIF (via taxa_build_gbif_crosswalk()), and their
#'     rows are appended to it. If there are no new names, GBIF matching is
#'     skipped. If no crosswalk file exists yet, a full one is built.
#'   new_crosswalk = TRUE: the saved crosswalk is ignored and every name in df
#'     is re-queried against GBIF from scratch; the result overwrites the file.
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
#' in df has changed -- use new_crosswalk = TRUE for that.
#'
#' Every column is stored as character (GBIF usageKeys are alphanumeric, and
#' it keeps saved and newly queried rows the same type when combined).
#' @param df data frame with taxa1_scientific, taxa1_group,
#'   taxa2_scientific, taxa2_group
#' @param crosswalk_path path to the crosswalk CSV (read if it exists, always
#'   written)
#' @param manual_matches_path path to the manual GBIF matches CSV (created
#'   if it doesn't exist)
#' @param new_crosswalk TRUE = rebuild the whole crosswalk from fresh GBIF
#'   queries; FALSE = only query names not already in the crosswalk
#' @returns the updated crosswalk (also written to crosswalk_path), with a
#'   final_canonicalName column holding the accepted GBIF name
harmonize_taxonomy_gbif <- function(
  df,
  crosswalk_path,
  manual_matches_path,
  new_crosswalk = FALSE
) {
  taxa_cols <- c(
    "taxa1_scientific",
    "taxa1_group",
    "taxa2_scientific",
    "taxa2_group"
  )
  stopifnot(all(taxa_cols %in% names(df)))

  # every unique (name, group) pair across both taxa columns. Pairs, not just
  # names, so taxa_resolve_group_conflicts() can still catch a new name that
  # was entered under two different groups.
  taxa <- rbind(
    data.frame(
      raw_name = df$taxa1_scientific,
      taxa_group = df$taxa1_group,
      stringsAsFactors = FALSE
    ),
    data.frame(
      raw_name = df$taxa2_scientific,
      taxa_group = df$taxa2_group,
      stringsAsFactors = FALSE
    )
  )
  taxa <- unique(taxa[!is.na(taxa$raw_name), ])

  # decide which names to query
  if (new_crosswalk) {
    message(
      "harmonize_taxonomy_gbif(): new_crosswalk = TRUE -- re-querying ",
      "all names against GBIF."
    )
    existing <- NULL
    to_query <- taxa
  } else if (!file.exists(crosswalk_path)) {
    message(
      "harmonize_taxonomy_gbif(): no crosswalk at ",
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
      "harmonize_taxonomy_gbif(): no new names -- skipping GBIF matching."
    )
    crosswalk <- existing
  } else {
    message("harmonize_taxonomy_gbif(): querying GBIF for ", n_new, " name(s).")
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
    "harmonize_taxonomy_gbif(): wrote ",
    nrow(crosswalk),
    " row(s) to ",
    crosswalk_path
  )

  crosswalk
}

# ============================================================================
# CLEANER: ADD GBIF NAMES, FLAG UNRESOLVED NAMES
# ============================================================================

#' Harmonize taxa1/taxa2 names to GBIF and flag names that don't resolve
#'
#' Runs harmonize_taxonomy_gbif() (queries GBIF for any name not yet in the
#' crosswalk, applies manual matches), then for each of taxa1_scientific and
#' taxa2_scientific:
#'   - resolved name: fills tx<n>_gbif (accepted GBIF name, taken from the
#'     crosswalk column named for final_rank -- "species", "subspecies",
#'     "genus", ...), tx<n>_gbif_rank and tx<n>_gbif_usageKey
#'   - unresolved name: leaves them NA and adds an `on_invalid` note telling
#'     you to fix the typo (and delete its manual-matches row) or fill in a
#'     manual usageKey
#'   - confirmed_no_match (NO_MATCH in the manual-matches CSV): leaves them
#'     NA and adds an `on_invalid` note telling you to remove the interaction
#'     from the source file
#' Rows with a blank (NA) name are skipped -- check_mandatory_fields()
#' handles missing values. No rows are dropped here; with on_invalid =
#' "error", move_flagged_files() removes the flagged file's rows.
#'
#' Messages start with "<column>: " and contain no "; ", so
#' move_flagged_files() splits them correctly.
#' @param df data frame with taxa1/taxa2 scientific and group columns
#' @param crosswalk_path path to the GBIF crosswalk CSV
#' @param manual_matches_path path to the manual GBIF matches CSV
#' @param new_crosswalk passed to harmonize_taxonomy_gbif()
#' @param on_invalid "error" (flags the file) or "warning"
#' @returns df with tx1_gbif, tx1_gbif_rank, tx1_gbif_usageKey, tx2_gbif,
#'   tx2_gbif_rank, tx2_gbif_usageKey added and notes appended
check_taxa_gbif <- function(
  df,
  crosswalk_path,
  manual_matches_path,
  new_crosswalk = FALSE,
  on_invalid = c("error", "warning")
) {
  on_invalid <- match.arg(on_invalid)

  crosswalk <- harmonize_taxonomy_gbif(
    df,
    crosswalk_path = crosswalk_path,
    manual_matches_path = manual_matches_path,
    new_crosswalk = new_crosswalk
  )

  resolved_statuses <- c("matched", "matched_fuzzy_high_confidence", "manual")
  crosswalk_resolved <- crosswalk$match_status %in%
    resolved_statuses &
    !is.na(crosswalk$final_usageKey) &
    !is.na(crosswalk$final_rank)
  manual_file <- basename(manual_matches_path)

  # status shown in error messages: a resolved status whose accepted
  # taxonomy lookup failed gets a clearer label
  status_label <- crosswalk$match_status
  lookup_failed <- crosswalk$match_status %in%
    resolved_statuses &
    is.na(crosswalk$final_rank)
  status_label[
    lookup_failed
  ] <- "accepted taxonomy lookup failed, retried next run"

  # accepted name per crosswalk row = value of the column named for its
  # accepted rank (SUBSPECIES -> `subspecies`). If that column is missing or
  # blank (e.g. a rank GBIF reports without a classification column), fall
  # back to final_canonicalName.
  rank_col <- tolower(crosswalk$final_rank)
  crosswalk_gbif_name <- vapply(
    seq_len(nrow(crosswalk)),
    function(i) {
      if (!is.na(rank_col[i]) && rank_col[i] %in% names(crosswalk)) {
        as.character(crosswalk[[rank_col[i]]][i])
      } else {
        NA_character_
      }
    },
    character(1)
  )
  crosswalk_gbif_name <- dplyr::coalesce(
    crosswalk_gbif_name,
    crosswalk$final_canonicalName
  )

  # output column prefix = input name column
  name_cols <- c(tx1 = "taxa1_scientific", tx2 = "taxa2_scientific")

  for (prefix in names(name_cols)) {
    col <- name_cols[[prefix]]
    taxon_names <- df[[col]]

    idx <- match(taxon_names, crosswalk$raw_name) # NA = not in crosswalk
    status <- status_label[idx]
    status[is.na(status)] <- "not in crosswalk"
    resolved <- !is.na(idx) & crosswalk_resolved[idx]

    df[[paste0(prefix, "_gbif")]] <- dplyr::if_else(
      resolved,
      crosswalk_gbif_name[idx],
      NA_character_
    )
    df[[paste0(prefix, "_gbif_rank")]] <- dplyr::if_else(
      resolved,
      crosswalk$final_rank[idx],
      NA_character_
    )
    df[[paste0(prefix, "_gbif_usageKey")]] <- dplyr::if_else(
      resolved,
      crosswalk$final_usageKey[idx],
      NA_character_
    )

    has_name <- !is.na(taxon_names)
    is_no_match <- has_name & status == "confirmed_no_match"
    is_unresolved <- has_name & !resolved & !is_no_match

    # not resolved yet: typo, or needs a manual usageKey
    rows <- which(is_unresolved)
    df <- add_note(
      df,
      rows,
      sprintf(
        paste0(
          "%s: '%s' could not be matched to GBIF (match_status = %s). ",
          "If this is a typo, correct it in the source file AND delete the ",
          "row for '%s' from %s. ",
          "If it is not a typo, enter the correct GBIF usageKey in the ",
          "manual_gbif_usageKey column for this raw_name in %s ",
          "(or NO_MATCH if GBIF has no match) and re-run."
        ),
        col,
        taxon_names[rows],
        status[rows],
        taxon_names[rows],
        manual_file,
        manual_file
      ),
      on_invalid
    )

    # reviewed and confirmed to have no GBIF match: interaction not allowed
    rows <- which(is_no_match)
    df <- add_note(
      df,
      rows,
      sprintf(
        paste0(
          "%s: '%s' has no GBIF match (marked NO_MATCH in %s). ",
          "Interactions with a taxon that has no GBIF match are not allowed ",
          "in the dataset -- remove this interaction from the source file. ",
          "If the name is actually a typo, correct it in the source file ",
          "AND delete the row for '%s' from %s instead."
        ),
        col,
        taxon_names[rows],
        manual_file,
        taxon_names[rows],
        manual_file
      ),
      on_invalid
    )

    message(
      "check_taxa_gbif(): ",
      col,
      " -- ",
      sum(resolved & has_name),
      " row(s) resolved, ",
      sum(is_unresolved),
      " unresolved, ",
      sum(is_no_match),
      " confirmed no match (all unresolved/no-match logged as ",
      on_invalid,
      ")."
    )
  }

  df
}
