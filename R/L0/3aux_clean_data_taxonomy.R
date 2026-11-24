# TITLE:            3a_aux_clean_data_taxonomy.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar, Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas,
#                   Minyoung Lee, Patrick Bills
# DATA INPUT:       Called from clean_data() in 3_clean_data.R on the data
#                   frame after text cleaning (so taxon names are already
#                   standardized and typo-corrected). Reads no files itself:
#                   the crosswalk CSV
#                   (./docs/master_metanetworks_gbif_crosswalk.csv) and the
#                   manual-matches CSV
#                   (3aux_clean_data_taxonomy_gbif_manual_matches.csv) are
#                   read and written by taxa_update_gbif_crosswalk() in
#                   3aux_clean_data_taxonomy_harmonize_names_to_gbif.R; the
#                   paths are passed through from here.
# DATA OUTPUT:      df with six new columns -- tx1_gbif, tx1_gbif_rank,
#                   tx1_gbif_usageKey and the same for tx2 (accepted GBIF
#                   name, its rank, and its usageKey for taxa1_scientific /
#                   taxa2_scientific) -- and an error appended for every name
#                   that doesn't resolve.
#                   The two CSVs above are updated as a side effect of the
#                   GBIF script (new names appended to the crosswalk, newly
#                   flagged names appended to the manual-matches registry).
# DATE:             initiated: 6 October 2026; last updated November 2026
# OVERVIEW:         Taxonomy step of clean_data(), and the data-frame layer of
#                   the taxonomy code: this script is the only one that knows
#                   the MetaNetworks column names (taxa1_scientific,
#                   taxa2_group, ...) and the clean_data() note/flagging
#                   contract. All GBIF and crosswalk knowledge lives in
#                   3aux_clean_data_taxonomy_harmonize_names_to_gbif.R, and
#                   this script reaches it only through that script's
#                   accessors -- it never reads a crosswalk column or
#                   hard-codes a match_status value.
#
#                   For the taxa1/taxa2 names:
#                     1. standardize_taxon_names(): column-specific text
#                        cleaning of the scientific and common name columns.
#                     2. harmonize_taxonomy_gbif(): pulls the unique
#                        (name, taxa_group) pairs out of the taxa1_*/taxa2_*
#                        columns and hands them to
#                        taxa_update_gbif_crosswalk(), which does the GBIF
#                        querying, the manual-match cycle, and the crosswalk
#                        file I/O.
#                     3. check_taxa_gbif(): each row's names are looked up in
#                        the updated crosswalk with taxa_crosswalk_lookup().
#                        Resolved names fill tx1_gbif / tx2_gbif with the
#                        accepted GBIF name. Unresolved names get an error
#                        (so the source file is flagged) telling you to fix
#                        the typo or fill in a manual usageKey.
#                   Which match_status values count as "resolved" is defined
#                   once, in taxa_resolved_statuses() in the GBIF script --
#                   not here. A resolved status whose accepted-taxonomy
#                   lookup failed is also treated as unresolved and gets its
#                   own label from taxa_match_status_label().
#                   A name marked NO_MATCH in the manual-matches CSV
#                   (confirmed_no_match) is also an error: interactions with
#                   a taxon that has no GBIF match are not allowed in the
#                   dataset. Following this script's contract (never drop
#                   rows), the row is not removed here -- the error flags the
#                   file, move_flagged_files() drops all of its rows, and the
#                   fix is to delete that interaction from the source file.
#                   The file stays flagged on every run until that's done.
# REQUIRES:         ./R/L0/3aux_clean_data_taxonomy_harmonize_names_to_gbif.R
#                   (sourced below, for taxa_update_gbif_crosswalk() and
#                   taxa_crosswalk_lookup()).
#                   ./R/L0/3aux_clean_data_basic_formatting.R, for add_note().
#                   dplyr is used namespace-qualified; neither sourced script
#                   attaches packages, so 3_clean_data.R is responsible for
#                   any library() calls it needs.
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
# NOTE:              Original version of this code was manually created, but was refactored and
#                    comments were added using AI. All code was human-reviewed after refactoring.

source("./R/L0/3aux_clean_data_basic_formatting.R")
source("./R/L0/3aux_clean_data_taxonomy_harmonize_names_to_gbif.R")

#' Standardize taxa1/taxa2 scientific and common name columns
#'
#'   - fixes missing space after "unid." (e.g. "unid.duck" -> "unid. duck")
#'   - standardizes "spp." to "sp."
#'   - sentence-cases scientific names (except entries starting "unid.")
#'   - title-cases common names
#' Each changed value is logged as a warning with the original value.
#' @param df harmonized data frame
#' @returns df
standardize_taxon_names <- function(df) {
  sci_cols <- intersect(c("taxa1_scientific", "taxa2_scientific"), names(df))
  common_cols <- intersect(c("taxa1_common", "taxa2_common"), names(df))

  for (col in sci_cols) {
    original <- df[[col]]
    x <- original
    x <- gsub("(?i)unid\\.(?=[A-Za-z])", "unid. ", x, perl = TRUE)
    x <- gsub("(?i)\\bundi\\.\\s*(?=[A-Za-z])", "unid. ", x, perl = TRUE)
    x <- gsub("\\bspp\\.", "sp.", x)

    non_na <- !is.na(x)
    is_unid <- non_na & grepl("(?i)^unid\\.", x)
    to_sentence <- non_na & !is_unid
    if (any(to_sentence)) {
      v <- x[to_sentence]
      x[to_sentence] <- paste0(
        toupper(substring(v, 1, 1)),
        tolower(substring(v, 2))
      )
    }
    x <- gsub(" {2,}", " ", x)

    changed <- which(!is.na(original) & !is.na(x) & original != x)
    df <- add_note(
      df,
      changed,
      paste0(col, ": standardized from '", original[changed], "'"),
      "warning"
    )
    df[[col]] <- x
  }

  for (col in common_cols) {
    original <- df[[col]]
    x <- original
    x <- gsub("(?i)\\bundi\\.?\\s+(?=[A-Za-z])", "unid. ", x, perl = TRUE)
    x <- gsub("(?i)\\bundi\\.(?=[A-Za-z])", "unid. ", x, perl = TRUE)
    x <- gsub("(?i)\\bunid[. ]+", "unid. ", x, perl = TRUE)
    x <- gsub("\\bspp\\.", "sp.", x)
    x <- gsub(" {2,}", " ", x)
    x <- trimws(x)

    non_na <- !is.na(x)
    if (any(non_na)) {
      words <- strsplit(x[non_na], " ")
      x[non_na] <- vapply(
        words,
        function(w) {
          paste(
            toupper(substring(w, 1, 1)),
            tolower(substring(w, 2)),
            sep = "",
            collapse = " "
          )
        },
        character(1)
      )
    }

    changed <- which(!is.na(original) & !is.na(x) & original != x)
    df <- add_note(
      df,
      changed,
      paste0(col, ": standardized from '", original[changed], "'"),
      "warning"
    )
    df[[col]] <- x
  }

  df
}

# ============================================================================
# UPDATE (OR REBUILD) THE CROSSWALK
# ============================================================================

#' Update (or rebuild) the GBIF taxonomy crosswalk for the names in df
#'
#' Pulls every (name, taxa_group) pair out of the taxa1_* and taxa2_* columns
#' and hands them to taxa_update_gbif_crosswalk(), which does the rest: GBIF
#' querying (incremental or full rebuild), the manual-match cycle, accepted
#' taxonomy, and reading/writing the crosswalk CSV. See that function in
#' 3aux_clean_data_taxonomy_harmonize_names_to_gbif.R for the details of
#' incremental vs. rebuild behaviour.
#'
#' This wrapper exists only to keep the df -> (raw_name, taxa_group)
#' translation on the data-frame side of the split, and to keep the call
#' signature clean_data() already uses.
#' @param df data frame with taxa1_scientific, taxa1_group,
#'   taxa2_scientific, taxa2_group
#' @param crosswalk_path path to the crosswalk CSV (read if it exists, always
#'   written)
#' @param manual_matches_path path to the manual GBIF matches CSV (created
#'   if it doesn't exist)
#' @param new_crosswalk TRUE = rebuild the whole crosswalk from fresh GBIF
#'   queries; FALSE = only query names not already in the crosswalk
#' @returns the updated crosswalk (also written to crosswalk_path)
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

  # every (name, group) pair across both taxa columns. Pairs, not just names,
  # so taxa_resolve_group_conflicts() can still catch a new name that was
  # entered under two different groups. Deduplication and NA-dropping happen
  # in taxa_update_gbif_crosswalk().
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

  taxa_update_gbif_crosswalk(
    taxa = taxa,
    crosswalk_path = crosswalk_path,
    manual_matches_path = manual_matches_path,
    new_crosswalk = new_crosswalk
  )
}

# ============================================================================
# CLEANER: ADD GBIF NAMES, FLAG UNRESOLVED NAMES
# ============================================================================

#' Harmonize taxa1/taxa2 names to GBIF and flag names that don't resolve
#'
#' Runs harmonize_taxonomy_gbif() (queries GBIF for any name not yet in the
#' crosswalk, applies manual matches), then looks each row's names up with
#' taxa_crosswalk_lookup() and, for each of taxa1_scientific and
#' taxa2_scientific:
#'   - resolved name: fills tx<n>_gbif (accepted GBIF name),
#'     tx<n>_gbif_rank and tx<n>_gbif_usageKey
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

  manual_file <- basename(manual_matches_path)

  # output column prefix = input name column
  name_cols <- c(tx1 = "taxa1_scientific", tx2 = "taxa2_scientific")

  for (prefix in names(name_cols)) {
    col <- name_cols[[prefix]]
    taxon_names <- df[[col]]

    # one row per row of df, in order: resolved, match_status, gbif_name,
    # gbif_rank, gbif_usageKey
    hit <- taxa_crosswalk_lookup(crosswalk, taxon_names)

    df[[paste0(prefix, "_gbif")]] <- hit$gbif_name
    df[[paste0(prefix, "_gbif_rank")]] <- hit$gbif_rank
    df[[paste0(prefix, "_gbif_usageKey")]] <- hit$gbif_usageKey

    has_name <- !is.na(taxon_names)
    is_no_match <- has_name & hit$match_status == "confirmed_no_match"
    is_unresolved <- has_name & !hit$resolved & !is_no_match

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
        hit$match_status[rows],
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
      sum(hit$resolved & has_name),
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
