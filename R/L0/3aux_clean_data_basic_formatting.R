# TITLE:            Basic cleaning functions for the harmonized data frame
# PROJECT:          AvianMetaNetwork
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:    Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas, Minyoung Lee, Patrick Bills
# DATA INPUT:       None (function definitions only). Every function takes the
#                   harmonized data frame `df` (from
#                   2_harmonize_datasheet_versions.R) plus whatever else it
#                   needs as explicit arguments.
# DATA OUTPUT:      None. Every function returns `df` with notes appended to
#                   the `errors` and/or `warnings` columns.
# DATE:             initiated: 29 Sep 2026
# OVERVIEW:         Basic (not column-specific) cleaning and validation steps,
#                   split out of clean_data.R so the master script only
#                   orchestrates. Sourced by clean_data.R.
#
#                   Shared contract for every function here (and for the
#                   column-specific cleaners in clean_data_<column>.R):
#                     - takes `df`, returns `df` (same rows, same order)
#                     - never drops rows
#                     - notes go in `errors` / `warnings`, joined with "; "
#                     - routine fixes are always logged as warnings
#                     - values that can't be fixed are logged as an error if
#                       the column is mandatory, otherwise as a warning
# REQUIRES:         Nothing (base R only)
# NOTES:            Row numbers in notes are not used; the note lives on the
#                   row it describes.

# ============================================================================
# NOTE HELPERS
# ============================================================================

#' Make sure the errors and warnings columns exist
#' @param df data frame
#' @returns df with `errors` and `warnings` columns (NA if newly created)
init_note_cols <- function(df) {
  if (!"errors" %in% names(df)) {
    df$errors <- NA_character_
  }
  if (!"warnings" %in% names(df)) {
    df$warnings <- NA_character_
  }
  df
}

#' Append a note to the errors or warnings column for specific rows
#'
#' If a row already has a note, the new one is added after "; ".
#' @param df data frame
#' @param rows integer vector of row indices to annotate
#' @param note character; one note (recycled) or one per row
#' @param type "error" or "warning"
#' @returns df with the note(s) appended
add_note <- function(df, rows, note, type = c("error", "warning")) {
  type <- match.arg(type)
  if (length(rows) == 0) {
    return(df)
  }
  df <- init_note_cols(df)
  target <- if (type == "error") "errors" else "warnings"

  existing <- df[[target]][rows]
  df[[target]][rows] <- ifelse(
    is.na(existing),
    note,
    paste(existing, note, sep = "; ")
  )
  df
}

#' Decide what an invalid value in a column should trigger
#' @param col column name
#' @param mandatory_cols character vector of mandatory column names
#' @returns "error" if col is mandatory, otherwise "warning"
on_invalid_for <- function(col, mandatory_cols) {
  if (col %in% mandatory_cols) "error" else "warning"
}

# ============================================================================
# TEXT CLEANING (run before column-specific cleaning)
# ============================================================================

#' Collapse internal double (or more) spaces in every character column
#'
#' Leading/trailing trim and blank/"NA"-string handling already happened in
#' clean_na() during harmonization. This only handles runs of 2+ spaces in
#' the middle of a value. Logs nothing.
#' @param df harmonized data frame
#' @returns df
clean_collapse_spaces <- function(df) {
  char_cols <- names(df)[vapply(df, is.character, logical(1))]
  for (col in char_cols) {
    df[[col]] <- gsub(" {2,}", " ", df[[col]])
  }
  df
}

#' Strip thousands-separator commas from numeric-typed schema columns
#'
#' Only touches values that look unambiguously like a comma-grouped number
#' (e.g. "1,234"), so they don't fail numeric coercion later. Each change is
#' logged as a warning.
#' @param df harmonized data frame (numeric columns still character)
#' @param numeric_cols character vector of columns the schema says are
#'   numeric or integer
#' @returns df
clean_numeric_commas <- function(df, numeric_cols) {
  pattern <- "^-?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$"

  for (col in intersect(numeric_cols, names(df))) {
    if (!is.character(df[[col]])) {
      next
    }
    trimmed <- trimws(df[[col]])
    rows <- which(!is.na(trimmed) & grepl(pattern, trimmed))
    if (length(rows) == 0) {
      next
    }
    df <- add_note(
      df,
      rows,
      paste0(col, ": comma removed from number '", trimmed[rows], "'"),
      "warning"
    )
    df[[col]][rows] <- gsub(",", "", trimmed[rows])
  }
  df
}

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
    x <- gsub("(?i)unid[. ]+", "unid. ", x, perl = TRUE)
    x <- gsub(" {2,}", " ", x)

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

#' Correct known typos in the interaction column using a lookup table
#'
#' Each corrected value is logged as a warning with the original value.
#' @param df harmonized data frame
#' @param corrections data frame with columns "incorrect" and "correct"
#' @returns df
correct_known_typos <- function(df, corrections) {
  if (!"interaction" %in% names(df)) {
    return(df)
  }

  original <- df$interaction
  match_idx <- match(
    tolower(trimws(original)),
    tolower(trimws(corrections$incorrect))
  )
  rows <- which(!is.na(match_idx))

  df$interaction[rows] <- corrections$correct[match_idx[rows]]
  add_note(
    df,
    rows,
    paste0("interaction: typo corrected from '", original[rows], "'"),
    "warning"
  )
}

#' Log rows where source_url_backfilled was set during harmonization
#'
#' reshape_sources() in 2_harmonize_datasheet_versions.R backfills a blank
#' sourceB/C/D_URL from sourceA_URL when the paired notes column has content.
#' That substitution changes data, so it is logged as a warning. The helper
#' column is then dropped, since it is bookkeeping and not part of the output
#' schema. No-op if the column doesn't exist.
#' @param df harmonized data frame
#' @returns df without the source_url_backfilled column
flag_backfilled_urls <- function(df) {
  if (!"source_url_backfilled" %in% names(df)) {
    return(df)
  }

  rows <- which(df$source_url_backfilled)
  df <- add_note(
    df,
    rows,
    "source_URL: backfilled from sourceA_URL",
    "warning"
  )
  df$source_url_backfilled <- NULL
  df
}

# ============================================================================
# VALIDATION AND TYPING (run after column-specific cleaning)
# ============================================================================

#' Flag implausible latitude/longitude values
#'
#' Must run BEFORE coerce_col_types(), while values are still the original
#' strings: DMS-formatted values are caught here, since after numeric
#' coercion they'd already be NA. Does not modify values. Values that are
#' simply non-numeric are not checked here; coerce_col_types() reports those.
#' Invalid values are an error if the column is mandatory, otherwise a
#' warning.
#' @param df harmonized data frame (latitude/longitude still character)
#' @param mandatory_cols character vector of mandatory column names
#' @returns df
validate_latlon <- function(df, mandatory_cols) {
  dms_pattern <- "[\u00b0'\"]|\\bN\\b|\\bS\\b|\\bE\\b|\\bW\\b"

  check_one <- function(df, col, bound, mandatory_cols, dms_pattern) {
    if (!col %in% names(df)) {
      return(df)
    }
    type <- on_invalid_for(col, mandatory_cols)
    vals <- trimws(df[[col]])
    non_na <- !is.na(vals)

    looks_dms <- non_na & grepl(dms_pattern, vals)
    rows <- which(looks_dms)
    df <- add_note(
      df,
      rows,
      paste0(col, ": '", vals[rows], "' looks like DMS, not decimal degrees"),
      type
    )

    numeric_vals <- suppressWarnings(as.numeric(vals))
    out_of_range <- non_na &
      !is.na(numeric_vals) &
      (numeric_vals < -bound | numeric_vals > bound)
    rows <- which(out_of_range)
    df <- add_note(
      df,
      rows,
      paste0(col, ": '", vals[rows], "' outside +/-", bound),
      type
    )
    df
  }

  df <- check_one(df, "latitude", 90, mandatory_cols, dms_pattern)
  df <- check_one(df, "longitude", 180, mandatory_cols, dms_pattern)
  df
}

#' Coerce every schema column to its declared data_format
#'
#' For numeric/integer columns, any value that had content but fails to
#' parse becomes NA and is logged (with the original value). Logged as an
#' error if the column is mandatory, otherwise a warning.
#' @param df harmonized data frame
#' @param schema data frame from column_names.csv (columns: column_name,
#'   data_format, ...)
#' @param mandatory_cols character vector of mandatory column names
#' @returns df with columns converted
coerce_col_types <- function(df, schema, mandatory_cols) {
  for (i in seq_len(nrow(schema))) {
    col <- schema$column_name[i]
    fmt <- schema$data_format[i]
    if (!col %in% names(df)) {
      next
    }

    original <- df[[col]]
    converted <- switch(
      fmt,
      integer = suppressWarnings(as.integer(original)),
      numeric = suppressWarnings(as.numeric(original)),
      factor = as.factor(original),
      character = as.character(original),
      original
    )

    if (fmt %in% c("integer", "numeric")) {
      rows <- which(!is.na(original) & is.na(converted))
      df <- add_note(
        df,
        rows,
        paste0(col, ": could not convert '", original[rows], "' to ", fmt),
        on_invalid_for(col, mandatory_cols)
      )
    }

    df[[col]] <- converted
  }
  df
}

#' Log rows with a missing value in a mandatory column
#'
#' Checks whatever is NA at this point, whether originally blank or NA'd by
#' a failed type coercion. Always an error. Run this LAST so that NAs filled
#' in by column-specific cleaners aren't flagged.
#' @param df cleaned + type-coerced data frame
#' @param mandatory_cols character vector of mandatory column names
#' @returns df
check_mandatory_fields <- function(df, mandatory_cols) {
  for (col in intersect(mandatory_cols, names(df))) {
    rows <- which(is.na(df[[col]]))
    df <- add_note(
      df,
      rows,
      paste0(col, ": missing mandatory value"),
      "error"
    )
  }
  df
}
