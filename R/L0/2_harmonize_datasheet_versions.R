# TITLE:            Harmonize data sheet schema versions
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar, Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas,
#                   Minyoung Lee, Patrick Bills
# DATA INPUT:       CSV files listed in aux_files_with_schema.csv (path: ./R/L0/aux_files_with_schema.csv),
#                    each tagged with a schema_name (schema_1 through schema_10) identifying which of
#                    the historical column layouts that file was collected under
# DATA OUTPUT:      A single, harmonized data frame combining every schema (schema_1 through
#                    schema_10) into the latest unified column structure, with an original_version
#                    column recording which meaningful version each row's source file came in as
# DATE:             initiated: August 2026; last updated: October 2026
# OVERVIEW:         Harmonizes each raw data sheet to the newest schema, one file at a time.
#                    A small registry maps each schema_name to (a) the meaningful "version" of the
#                    data collection protocol that it represents, and (b) any column-naming quirks specific
#                    to that schema that need fixing before it matches its version's canonical shape.
#                    A second registry holds one "upgrader" per version transition (v1->v2, v2->v3,
#                    v3->v4), capturing only the changes that reflect real changes to the data
#                    (as opposed to incidental naming differences between data sheets of the same
#                    version). harmonize_datasheet() runs a single file through its schema fix and then
#                    the chain of version upgraders up to the newest version, tagging the file with
#                    original_version along the way so that tag is never touched again.
# NOTE:              "Schemas" represent unique combinations of columns in the MetaNetworks
#                    CSVs. Sometimes these column combinations were the result of deliberate changes
#                    in the data sheet and other time, they were accidental misspellings or deletions.
#                    All schemas are assigned to the appropriate major "version" of the data in the
#                    this script.
#
#                    To add a schema in the future: add one entry to schema_registry with its version
#                    and any needed column fixes. To add a new version: append it to version_sequence
#                    and add one function to version_upgraders for the new transition. Nothing else in
#                    this file needs to change.
#
# NOTE:              Original version of this code was manually created, but was refactored and
#                    comments were added using AI. All code was human-reviewed after refactoring.

# Harmonize data sheet versions

library(tidyverse)

file_info_path <- "./R/L0/1_files_with_schema.csv"
file_info <- read.csv(file_info_path)

# Skip files with no real content -- a header-only sheet, or one where every
# cell is NA/blank -- before they ever reach harmonize_datasheet().
n_before <- nrow(file_info)
file_info <- file_info |> filter(is.na(has_content) | has_content)
n_skipped <- n_before - nrow(file_info)
if (n_skipped > 0) {
  message(sprintf(
    "Skipping %d blank/empty file(s) before harmonizing.",
    n_skipped
  ))
}

# ============================================================================
# GENERIC HELPER FUNCTIONS
# ============================================================================

# Collapse several old columns into one new column per row, keeping only
# unique, non-blank values and joining them with "; "; drops the old columns
# (except when old_cols and new_col overlap)
concatenate_cols <- function(df, old_cols, new_col) {
  df |>
    mutate(across(all_of(old_cols), as.character)) |>
    rowwise() |>
    mutate(
      !!new_col := c_across(all_of(old_cols)) |>
        keep(~ !is.na(.x) & str_trim(.x) != "") |>
        unique() |>
        str_c(collapse = "; ")
    ) |>
    ungroup() |>
    select(-all_of(setdiff(old_cols, new_col)))
}

# Trim whitespace and convert blank/"NA" strings to true NA across all
# character columns in a data frame
clean_na <- function(df) {
  df[] <- lapply(df, function(x) {
    if (is.character(x)) {
      x <- trimws(x)
      x[x %in% c("", "NA")] <- NA
    }
    x
  })
  df
}

# Check whether a vector's values are non-missing and non-blank after trimming
has_content <- function(x) {
  x <- trimws(as.character(x))
  !is.na(x) & x != "" & x != "NA"
}

# Add each named column as NA if it isn't already present in df; leaves any
# column that already exists untouched. Used by version upgraders to add
# fields that only started being tracked as of that version, without
# clobbering the real values already present in a schema that already
# collected them (or that was already carried through a prior upgrade step).
add_missing_cols <- function(df, cols, fill = NA_character_) {
  for (col in cols) {
    if (!col %in% names(df)) {
      df[[col]] <- rep(fill, nrow(df))
    }
  }
  df
}

# Reshape a wide data frame with multiple paired source-URL/notes columns
# into a long format with one source_URL / text_excerpt pair per row,
# dropping rows where both the URL and notes are empty; preserves original
# row order via a temporary .orig_row index.
#
# BACKFILL: if a later source's URL column (e.g. sourceB_URL) is blank but
# its paired notes column (e.g. notesB) has content, the URL is backfilled
# from the FIRST url column (url_cols[1], e.g. sourceA_URL) -- this covers
# entries where the same source was cited multiple times but the URL was
# only typed once, in sourceA. Backfilled rows are tagged
# source_url_backfilled = TRUE (rather than silently substituting the value)
# so the downstream audit script can flag and report on them instead of
# letting the substitution pass unnoticed.
reshape_sources <- function(df, url_cols, notes_cols, id_cols = NULL) {
  stopifnot(length(url_cols) == length(notes_cols))

  missing_cols <- setdiff(c(url_cols, notes_cols), names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "reshape_sources(): df is missing expected column(s): %s",
      paste(missing_cols, collapse = ", ")
    ))
  }

  if (is.null(id_cols)) {
    id_cols <- setdiff(names(df), c(url_cols, notes_cols))
  }

  df$.orig_row <- seq_len(nrow(df))
  primary_url <- df[[url_cols[1]]]

  pieces <- lapply(seq_along(url_cols), function(i) {
    u <- df[[url_cols[i]]]
    n <- df[[notes_cols[i]]]
    keep <- has_content(u) | has_content(n)

    out <- df[keep, id_cols, drop = FALSE]
    u_keep <- u[keep]
    n_keep <- n[keep]

    backfilled <- rep(FALSE, length(u_keep))
    if (i > 1) {
      needs_backfill <- !has_content(u_keep) & has_content(n_keep)
      u_keep[needs_backfill] <- primary_url[keep][needs_backfill]
      backfilled[needs_backfill] <- TRUE
    }

    out$source_URL <- ifelse(has_content(u_keep), u_keep, NA_character_)
    out$text_excerpt <- ifelse(has_content(n_keep), n_keep, NA_character_)
    out$source_url_backfilled <- backfilled
    out$.orig_row <- df$.orig_row[keep]
    out
  })

  result <- do.call(rbind, pieces)
  result <- result[order(result$.orig_row), ]
  result$.orig_row <- NULL
  rownames(result) <- NULL

  result$source_URL <- as.character(result$source_URL)
  result$text_excerpt <- as.character(result$text_excerpt)

  result
}

# ============================================================================
# SCHEMA REGISTRY
# Maps every schema_name to the (meaningful) version it represents, plus a
# `normalize` function that fixes whatever incidental column-naming quirks
# are specific to that one schema -- bringing it in line with the shared
# canonical shape for its version. Most schemas need no fixing at all.
#
# TO ADD A FUTURE SCHEMA: add one entry here. If it's a minor naming variant
# of an existing version, set normalize to whatever renames/reshapes bring it
# in line with that version's other schemas. If it represents a genuinely new
# version, see version_sequence / version_upgraders below instead.
# ============================================================================

# Shared fix for schema_1, schema_2, schema_4, schema_5, schema_6: rename
# the sourceX_updatedURL columns to the canonical sourceX_URL names, fold
# the old OLDsourceA/OLDsourceB entries into sourceA_URL, and rename
# nonbreedingseason to breeding_migration.
normalize_shared_v1v2_naming <- function(df) {
  df |>
    rename(
      sourceA_URL = sourceAupdatedURL,
      sourceB_URL = sourceBupdatedURL,
      sourceC_URL = sourceCupdatedURL,
      sourceD_URL = sourceDupdatedURL,
      breeding_migration = nonbreedingseason
    ) |>
    concatenate_cols(c("OLDsourceA", "OLDsourceB"), "Oldsource") |>
    concatenate_cols(c("Oldsource", "sourceA_URL"), "sourceA_URL")
}

schema_registry <- list(
  schema_1 = list(version = "v1", normalize = normalize_shared_v1v2_naming),

  schema_2 = list(
    version = "v1",
    normalize = function(df) {
      df |>
        normalize_shared_v1v2_naming() |>
        add_missing_cols("name_changes")
    }
  ),

  schema_5 = list(version = "v1", normalize = normalize_shared_v1v2_naming),

  schema_4 = list(version = "v2", normalize = normalize_shared_v1v2_naming),

  schema_6 = list(
    version = "v2",
    normalize = function(df) {
      df |>
        rename(DatabaseSearchURL = GoogleScholarURL) |>
        normalize_shared_v1v2_naming()
    }
  ),

  schema_8 = list(
    version = "v2",
    normalize = function(df) rename(df, breeding_migration = nonbreedingseason)
  ),

  schema_3 = list(version = "v3", normalize = function(df) df),

  schema_9 = list(
    version = "v3",
    normalize = function(df) rename(df, source_citation = Citation)
  ),

  schema_10 = list(
    version = "v3",
    normalize = function(df) mutate(df, source_citation = NA)
  ),

  schema_7 = list(version = "v4", normalize = function(df) df),

  schema_11 = list(version = "v5", normalize = function(df) df)
)

# ============================================================================
# VERSION UPGRADE CHAIN
# One function per transition, keyed by the version being upgraded FROM.
# Each captures only the changes that reflect a real change in what was
# collected -- never per-schema naming fixes (those belong in
# schema_registry above).
#
# TO ADD A FUTURE VERSION: append its name to version_sequence, and add a
# version_upgraders[["<previous latest version>"]] entry describing how to
# upgrade into it. Nothing else needs to change.
# ============================================================================

version_sequence <- c("v1", "v2", "v3", "v4", "v5")

version_upgraders <- list(
  # v1 -> v2: the one real difference is DatabaseSearchURL, a field that
  # starts at v2 and is absent from every v1 schema natively. v1 sheets get this
  # column added (empty) explicitly so the combined dataset has it consistently.
  v1 = function(df) add_missing_cols(df, "DatabaseSearchURL"),

  # v2 -> v3: the real change is collapsing the per-source sourceX_URL /
  # notesX wide columns into long source_URL / text_excerpt rows, and the
  # data started tracking life stage, interaction strength, time of year,
  # and source citation.
  v2 = function(df) {
    df |>
      reshape_sources(
        url_cols = c(
          "sourceA_URL",
          "sourceB_URL",
          "sourceC_URL",
          "sourceD_URL"
        ),
        notes_cols = c("notesA", "notesB", "notesC", "notesD")
      ) |>
      add_missing_cols(c(
        "species1_lifestage",
        "species2_lifestage",
        "interaction_strength",
        "time_of_year",
        "source_citation"
      ))
  },

  # v3 -> v4: rename to the taxa1/taxa2 convention (replacing the
  # species1/species2 naming used since v1), drop other_species1 (no longer
  # part of the unified schema), and add the fields that started being
  # tracked at v4.
  v3 = function(df) {
    if (!"source_url_backfilled" %in% names(df)) {
      df$source_url_backfilled <- rep(FALSE, nrow(df))
    }
    df |>
      rename(
        effect_tx1_on_tx2 = effect_sp1_on_sp2,
        effect_tx2_on_tx1 = effect_sp2_on_sp1,
        taxa1_common = species1_common,
        taxa2_common = species2_common,
        taxa1_scientific = species1_scientific,
        taxa2_scientific = species2_scientific,
        taxa1_lifestage = species1_lifestage,
        taxa2_lifestage = species2_lifestage,
        interaction_excerpt = text_excerpt,
        tx1_life_history_season = breeding_migration
      ) |>
      add_missing_cols(c(
        "n_studies",
        "BOW_evidence",
        "tx2_life_history_season",
        "country",
        "location",
        "timing_location_excerpt",
        "year"
      )) |>
      select(-any_of("other_species1"))
  },

  # v4 -> v5:
  #
  # # Convert effect_tx1_on_tx2 to effect_on_tx2 and vice versa.
  #
  # New fields as of v5: elevation, latitude, longitude (structured
  # geolocation alongside the existing free-text `location`),
  # interaction_confidence, notes, taxa1_resolution, taxa2_resolution.
  #
  # taxa1_group/taxa2_group are NOT added here even though schema_11 has real
  # data in them -- see finalize_harmonized_schema() below, which needs to
  # treat them differently (defaulting pre-v5 files to "bird" without
  # clobbering v5's real values).

  v4 = function(df) {
    df |>
      rename(
        effect_on_tx2 = effect_tx1_on_tx2,
        effect_on_tx1 = effect_tx2_on_tx1
      ) |>
      add_missing_cols(c(
        "elevation",
        "interaction_confidence",
        "latitude",
        "longitude",
        "notes",
        "taxa1_resolution",
        "taxa2_resolution"
      ))
  }
)

# ============================================================================
# FINAL SCHEMA CLEANUP
# Applied once, unconditionally, after every file has been brought up to the
# newest version -- regardless of whether it arrived there natively or via
# the upgrade chain. Drops a couple of confirmed-not-useful fields, and
# stamps the fields that are constant for this dataset.

# ============================================================================

finalize_harmonized_schema <- function(df) {
  df |>
    # Remove columns no longer deemed useful
    dplyr::select(-any_of(c("n_studies", "name_changes"))) |>
    # Add in taxa groups to v1 to v4 data sheets (assumed bird)
    add_missing_cols(c("taxa1_group", "taxa2_group"), fill = "bird") |>

    add_missing_cols("BOW_evidence") |>

    # Remove co-occur interactions
    filter(!coalesce(str_detect(str_to_lower(interaction), "occur"), FALSE)) |>
    # Remove rows with no taxa names or interaction (assumed erroneous extra rows)
    filter(
      !if_all(c(taxa1_scientific, taxa2_scientific, interaction), is.na)
    ) |>
    select(-any_of("version")) |>
    rename(version = original_version)
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Harmonize a single raw data sheet to the newest schema version.
#
# file:              path to one raw CSV
# schema_name:       which schema (schema_1, schema_2, ...) this file was
#                     registered under (see aux_schema_register.R)
# schema_registry:   named list, see above
# version_upgraders: named list, see above
# version_sequence:  character vector of versions oldest to newest, see above
#
# Returns the file's data harmonized to the newest version's columns, with
# original_version recording the (meaningful) version this file's schema
# natively belonged to -- set once, immediately after load, and never
# touched by anything downstream.
harmonize_datasheet <- function(
  file,
  schema_name,
  schema_registry,
  version_upgraders,
  version_sequence
) {
  if (!schema_name %in% names(schema_registry)) {
    stop(sprintf(
      paste(
        "Schema '%s' (file: %s) is not registered in schema_registry.",
        "Add an entry for it -- with its native version and any column",
        "fixes it needs -- before harmonizing this file."
      ),
      schema_name,
      file
    ))
  }

  schema_def <- schema_registry[[schema_name]]
  native_version <- schema_def$version

  if (!native_version %in% version_sequence) {
    stop(sprintf(
      "Schema '%s' is registered with version '%s', which is not present in version_sequence (%s).",
      schema_name,
      native_version,
      paste(version_sequence, collapse = ", ")
    ))
  }

  # 1. Load the raw file and tag it with the version it originally came in
  #    as. This column is never modified again by anything below.
  out <- read.csv(file, colClasses = "character") |>
    mutate(
      source_file = basename(file),
      original_version = native_version,
      source_row = row_number() + 1L
    )

  # 2. Fix up whatever column-naming quirks are specific to this one schema,
  #    so it matches the shared canonical shape for its native version.
  out <- schema_def$normalize(out)

  # 3. Walk the version chain from this file's native version up to the
  #    newest version, applying each transition's real (meaningful) change.
  from_index <- match(native_version, version_sequence)
  if (from_index < length(version_sequence)) {
    for (v in version_sequence[from_index:(length(version_sequence) - 1)]) {
      out <- version_upgraders[[v]](out)
    }
  }

  # 4. Apply the one-time cleanup that defines the final unified schema.
  out |>
    finalize_harmonized_schema() |>
    clean_na()
}

# Harmonize every file listed in file_info and combine the results.
# Uses dplyr::bind_rows() (rather than base rbind()) so this doesn't depend
# on every file ending up with identical columns in identical order -- any
# column missing for a given file is simply filled with NA in the combined
# result.
#
# NOTE TO KELLY TO DOUBLE CHECK BIND_ROWS ISN'T ADDING IN A BUNCH OF NA
# VALUES IN COLUMNS THAT SHOULD EXIST....
harmonize_all_datasheets <- function(
  file_info,
  schema_registry,
  version_upgraders,
  version_sequence
) {
  file_info |>
    purrr::pmap(function(file, schema_name, ...) {
      harmonize_datasheet(
        file,
        schema_name,
        schema_registry,
        version_upgraders,
        version_sequence
      )
    }) |>
    dplyr::bind_rows()
}

# ============================================================================
# RUN
# ============================================================================

harmonized_df <- harmonize_all_datasheets(
  file_info,
  schema_registry,
  version_upgraders,
  version_sequence
)

saveRDS(harmonized_df, "./R/L0/2_harmonized_df.rds")
