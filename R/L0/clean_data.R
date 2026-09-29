# TITLE:            Master cleaning script for the harmonized data frame
# PROJECT:          AvianMetaNetwork
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:    [FILL IN]
# DATA INPUT:       The harmonized data frame `df` produced by
#                   aux_harmonize_datasheet_versions.R (one row per
#                   interaction record, tagged with source_file), plus
#                   column_names.csv (schema with data_format and
#                   mandatory_col flags) and aux_interaction_corrections.csv
#                   (known interaction-type typos)
# DATA OUTPUT:      (1) df_clean: the full data frame with `errors` and
#                       `warnings` columns (nothing dropped)
#                   (2) df_final: df_clean minus every row from any source
#                       file with at least one error; those source files are
#                       moved to taxa_flagged
# DATE:             initiated: 10 Aug 2026; modularized 29 Sep 2026
# OVERVIEW:         Orchestrates cleaning in this order:
#                     1. basic text cleaning        (clean_data_basic.R)
#                     2. column-specific cleaning   (clean_data_<column>.R)
#                     3. validation and typing      (clean_data_basic.R)
#                   then, as a separate step, move_flagged_files().
#
#                   Mandatory columns are passed in as a character vector.
#                   Invalid values in a mandatory column are logged as
#                   errors; invalid values in any other column are logged as
#                   warnings. Only errors get a source file flagged.
#
#                   TO ADD A NEW COLUMN-SPECIFIC CLEANER:
#                     1. write clean_data_<column>.R defining a function with
#                        signature f(df, col, on_invalid = c("error",
#                        "warning")) that returns df with notes appended to
#                        `errors` / `warnings` (see add_note() in
#                        clean_data_basic.R)
#                     2. source() it below
#                     3. add one line to `column_cleaners` in the run section
# REQUIRES:         aux_harmonize_datasheet_versions.R (run first, so `df`
#                   exists), clean_data_basic.R, clean_data_life_history.R
# NOTES:            Run on fresh harmonizer output. Cleaners are not safe to
#                   run twice on the same data frame (e.g. already-recoded
#                   life history values would be flagged as unrecognized),
#                   so assign to a new object (df_clean) instead of
#                   overwriting df.

source("./R/L0/clean_data_basic_formatting.R")
source("./R/L0/clean_data_life_history.R")

# ============================================================================
# MASTER CLEANING FUNCTION
# ============================================================================

#' Run all basic, then column-specific, cleaning on the harmonized data frame
#'
#' Phase order matters:
#'   1. text cleaning first, so column-specific cleaners see tidy strings
#'   2. column-specific cleaners next, while values are still the original
#'      strings (type coercion would break string recoding)
#'   3. lat/long validation, type coercion, and the mandatory-field check
#'      last, so NAs filled in by cleaners aren't flagged as missing
#' @param df harmonized data frame (must have a source_file column)
#' @param schema data frame from column_names.csv (columns: column_name,
#'   data_format, ...)
#' @param corrections data frame with columns "incorrect" and "correct"
#' @param mandatory_cols character vector of mandatory column names; invalid
#'   values in these are errors, in all other columns warnings
#' @param column_cleaners named list: names are column names, values are
#'   cleaning functions with signature f(df, col, on_invalid)
#' @returns full data frame with `errors` and `warnings` columns; no rows
#'   are dropped
clean_data <- function(
  df,
  schema,
  corrections,
  mandatory_cols,
  column_cleaners
) {
  stopifnot("source_file" %in% names(df))
  numeric_cols <- schema$column_name[
    schema$data_format %in% c("numeric", "integer")
  ]

  df <- init_note_cols(df)

  # 1. basic text cleaning
  df <- clean_collapse_spaces(df)
  df <- clean_numeric_commas(df, numeric_cols)
  df <- standardize_taxon_names(df)
  df <- correct_known_typos(df, corrections)
  df <- flag_backfilled_urls(df)

  # 2. column-specific cleaning
  for (col in names(column_cleaners)) {
    if (!col %in% names(df)) {
      stop(
        "Column-specific cleaner registered for '",
        col,
        "' but df has no such column"
      )
    }
    df <- column_cleaners[[col]](
      df,
      col = col,
      on_invalid = on_invalid_for(col, mandatory_cols)
    )
  }

  # 3. validation and typing
  df <- validate_latlon(df, mandatory_cols)
  df <- coerce_col_types(df, schema, mandatory_cols)
  df <- check_mandatory_fields(df, mandatory_cols)

  df
}

# ============================================================================
# MOVE FLAGGED FILES
# ============================================================================

#' Move source files with at least one error into taxa_flagged
#'
#' Any file with a non-NA `errors` value in at least one row is moved out of
#' its current folder into `flagged_dir`, and ALL of its rows are removed
#' from the data frame. Files with only warnings are left alone. Every file
#' is located before anything is moved, so a missing file stops the function
#' with nothing moved.
#'
#' Note: the file is moved as-is (unmodified). The error messages live only
#' in the returned `flagged` data frame, not in the moved csv.
#'
#' `flagged` has one row per unique combination of source file, row number,
#' and error message. If `df` has a `row_col` column (source_row, stamped in
#' harmonize_datasheet() before any rows are dropped or reshaped), that is
#' the row number reported. Otherwise it falls back to the row's position
#' within its source file in `df`, which shifts if anything upstream removed
#' rows and requires that df hasn't been filtered or reordered. Messages are
#' split on "; " only where the next piece starts with "<column>: ", so
#' values that themselves contain "; " stay intact.
#' @param df cleaned data frame from clean_data() (needs `errors` and the
#'   file column)
#' @param source_dirs character vector of folders the source files might be
#'   in (e.g. taxa_to_check and taxa_checked_raw)
#' @param flagged_dir folder to move flagged files into (taxa_flagged)
#' @param file_col name of the column holding the source file name
#' @param row_col name of the column holding each row's original row number
#'   in its source file; if not in df, position within file is used instead
#' @returns list(data = df without rows from flagged files,
#'   flagged = data frame with columns source_file, row, error)
move_flagged_files <- function(
  df,
  source_dirs,
  flagged_dir,
  file_col = "source_file",
  row_col = "source_row"
) {
  stopifnot(file_col %in% names(df), "errors" %in% names(df))

  flagged_files <- unique(df[[file_col]][!is.na(df$errors)])
  in_flagged <- df[[file_col]] %in% flagged_files

  # one row per (file, row within file, individual error message)
  if (row_col %in% names(df)) {
    row_in_file <- df[[row_col]]
  } else {
    row_in_file <- ave(seq_len(nrow(df)), df[[file_col]], FUN = seq_along)
  }
  error_rows <- which(!is.na(df$errors))
  messages <- strsplit(
    df$errors[error_rows],
    "; (?=[A-Za-z0-9_]+: )",
    perl = TRUE
  )
  flagged <- data.frame(
    source_file = rep(df[[file_col]][error_rows], lengths(messages)),
    row = rep(row_in_file[error_rows], lengths(messages)),
    error = as.character(unlist(messages)),
    stringsAsFactors = FALSE
  )
  flagged <- unique(flagged)
  flagged <- flagged[order(flagged$source_file, flagged$row), ]
  rownames(flagged) <- NULL

  if (length(flagged_files) > 0) {
    # locate every file first
    from <- character(length(flagged_files))
    for (i in seq_along(flagged_files)) {
      candidates <- file.path(source_dirs, basename(flagged_files[i]))
      found <- candidates[file.exists(candidates)]
      if (length(found) != 1) {
        stop(
          length(found),
          " copies of '",
          flagged_files[i],
          "' found in source_dirs (expected exactly 1)"
        )
      }
      from[i] <- found
    }

    # then move them
    #   dir.create(flagged_dir, showWarnings = FALSE, recursive = TRUE)
    #   for (i in seq_along(flagged_files)) {
    #     to <- file.path(flagged_dir, basename(flagged_files[i]))
    #     if (!file.copy(from[i], to, overwrite = TRUE)) {
    #       stop("Could not copy '", from[i], "' to '", to, "'")
    #     }
    #     file.remove(from[i])
    #   }
    #   message("Moved ", length(flagged_files), " file(s) to ", flagged_dir)
  }

  list(data = df[!in_flagged, ], flagged = flagged)
}

# ============================================================================
# RUN
# ============================================================================

# paths -- adjust to your folder layout
schema_path <- "./docs/interaction_metadata_schemas/column_names.csv"
corrections_path <- "./R/L0/aux_interaction_corrections.csv"
source_dirs <- c(
  "../MetaNetworksProject-Working/L0/taxa_to_check",
  "../MetaNetworksProject-Working/L0/taxa_checked_raw"
)
flagged_dir <- "../MetaNetworksProject-Working/L0/taxa_flagged"

# expects df from source("./R/auxiliary_scripts/aux_harmonize_datasheet_versions.R")
stopifnot(exists("df"))

schema <- read.csv(schema_path, stringsAsFactors = FALSE)
schema <- schema[!is.na(schema$column_name), ]
corrections <- read.csv(corrections_path, stringsAsFactors = FALSE)

mandatory_cols <- schema$column_name[
  !is.na(schema$mandatory_col) & schema$mandatory_col == "x"
]

# one line per column-specific cleaner: column name = cleaning function
column_cleaners <- list(
  tx1_life_history_season = standardize_life_history_season
)

df_clean <- clean_data(
  df,
  schema = schema,
  corrections = corrections,
  mandatory_cols = mandatory_cols,
  column_cleaners = column_cleaners
)

result <- move_flagged_files(
  df_clean,
  source_dirs = source_dirs,
  flagged_dir = flagged_dir
)
df_final <- result$data
df_flagged <- result$flagged
