# TITLE:            [FILL IN]
# PROJECT:          AvianMetaNetwork
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:    [FILL IN]
# DATA INPUT:       The harmonized data frame `df` produced by
#                   aux_harmonize_datasheet_versions.R (one row per
#                   interaction record, tagged with source_file), plus
#                   column_names.csv (schema definition with data_format and
#                   mandatory_col flags) and aux_interaction_corrections.csv (known
#                   interaction-type typos)
# DATA OUTPUT:      (1) cleaned csv: harmonized data with standardized column
#                       types and corrected typos/inconsistencies. Exclusion
#                       is ROW-level: only rows missing a mandatory field are
#                       dropped, not the whole file they came from.
#                   (2) audit report csv: one row per source_file (wide
#                       format), with a flag_<column> indicator for every
#                       field that had at least one issue, an issue_summary
#                       column, an overall status (OK / WARNING / ERROR),
#                       and n_rows_excluded_error / excluded_rows_detail
#                       showing exactly which rows were dropped and why
# DATE:             initiated: 10 Aug 2026
# OVERVIEW:         Runs AFTER harmonization, on the single combined data
#                   frame -- not on raw per-file CSVs. All column names are
#                   hardcoded to the unified taxa1_*/effect_tx*_on_tx*
#                   naming, since by this point in the pipeline every file
#                   has already been renamed to one consistent schema.
#                   Cleaning steps (whitespace, numeric commas, taxon name
#                   standardization, known-typo correction, lat/long
#                   plausibility, type coercion) run first; every issue is
#                   logged with source_file/column/row rather than silently
#                   dropped. The mandatory-field check runs last, using
#                   whatever is still NA at that point (whether originally
#                   blank or NA'd out by a failed type coercion), and
#                   determines which files get excluded from the cleaned
#                   output and flagged ERROR in the audit report.
# REQUIRES:         aux_harmonize_datasheet_versions.R must be run first
#                   (this script expects `df` to already exist, with a
#                   source_file column)
# NOTES:            Whitespace TRIMMING and blank/"NA"-string handling is
#                   already done by clean_na() inside
#                   aux_harmonize_datasheet_versions.R -- this script only
#                   adds what that doesn't do (collapsing internal double
#                   spaces), rather than repeating the trim.

# ============================================================================
# SETUP
# ============================================================================

# expects df to already be in the environment from:
# source("./R/auxiliary_scripts/aux_harmonize_datasheet_versions.R")
stopifnot(exists("df"), "source_file" %in% names(df))

schema_path <- "./docs/interaction_metadata_schemas/column_names.csv"
corrections_path <- "./R/L0/aux_interaction_corrections.csv"
cleaned_output_path <- "./test_harmonized_output.csv"
audit_report_path <- "./test_audit_report.csv"

# ============================================================================
# HELPER: issues log
# ============================================================================

#' Start an empty issues log with the standard columns
#' @returns empty data frame: source_file, column, row, issue, detail
empty_issues_log <- function() {
  data.frame(
    source_file = character(),
    column = character(),
    row = integer(),
    issue = character(),
    detail = character(),
    stringsAsFactors = FALSE
  )
}

# ============================================================================
# CLEANING FUNCTIONS
# Each takes the full harmonized df (with source_file column) and returns
# list(data = <cleaned df>, issues = <issues log>). Row numbers in the log
# are row indices into `df` itself; source_file for each logged issue is
# looked up via df$source_file[row], so nothing needs to be run per-file.
# ============================================================================

#' Collapse internal double (or more) spaces in every character column
#'
#' Leading/trailing trim and blank/"NA"-string handling already happened in
#' clean_na() during harmonization -- this only handles what that doesn't:
#' runs of 2+ spaces in the middle of a value.
#' @param df harmonized data frame
#' @returns list(data = cleaned df, issues = issues log)
clean_collapse_spaces <- function(df) {
  issues <- empty_issues_log()
  char_cols <- names(df)[vapply(df, is.character, logical(1))]

  for (col in char_cols) {
    original <- df[[col]]
    cleaned <- gsub(" {2,}", " ", original)

    df[[col]] <- cleaned
  }

  list(data = df, issues = issues)
}

#' Strip thousands-separator commas from numeric-typed schema columns
#'
#' Only checks columns the schema says should be numeric/integer (e.g.
#' effect_tx1_on_tx2, year, latitude), and only touches values that look
#' unambiguously like a comma-grouped number (e.g. "1,234"). Runs before
#' coerce_col_types() so those commas don't cause an otherwise-valid number
#' to fail conversion.
#' @param df harmonized data frame (numeric-typed columns still character
#'   at this point)
#' @param numeric_cols character vector of column names that should end up
#'   numeric or integer, per the schema
#' @returns list(data = cleaned df, issues = issues log)
clean_numeric_commas <- function(df, numeric_cols) {
  issues <- empty_issues_log()
  pattern <- "^-?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$"

  cols <- intersect(numeric_cols, names(df))
  for (col in cols) {
    if (!is.character(df[[col]])) {
      next
    }
    vals <- df[[col]]
    trimmed <- trimws(vals)
    is_comma_number <- !is.na(vals) & grepl(pattern, trimmed)

    if (any(is_comma_number)) {
      rows <- which(is_comma_number)
      issues <- rbind(
        issues,
        data.frame(
          source_file = df$source_file[rows],
          column = col,
          row = rows,
          issue = "comma_stripped_from_number",
          detail = NA_character_,
          stringsAsFactors = FALSE
        )
      )
      df[[col]][is_comma_number] <- gsub(",", "", trimmed[is_comma_number])
    }
  }

  list(data = df, issues = issues)
}

#' Standardize taxa1/taxa2 scientific and common name columns
#'
#' Hardcoded to taxa1_scientific/taxa2_scientific/taxa1_common/taxa2_common
#' -- safe now that every row has already been renamed to this naming
#' during harmonization.
#'   - fixes missing space after "unid." (e.g. "unid.duck" -> "unid. duck")
#'   - standardizes "spp." to "sp."
#'   - sentence-cases scientific names (except entries starting "unid.")
#'   - title-cases common names
#' @param df harmonized data frame
#' @returns list(data = cleaned df, issues = issues log)
standardize_taxon_names <- function(df) {
  issues <- empty_issues_log()
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
    if (length(changed)) {
      issues <- rbind(
        issues,
        data.frame(
          source_file = df$source_file[changed],
          column = col,
          row = changed,
          issue = "scientific_name_standardized",
          detail = NA_character_,
          stringsAsFactors = FALSE
        )
      )
    }
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
    if (length(changed)) {
      issues <- rbind(
        issues,
        data.frame(
          source_file = df$source_file[changed],
          column = col,
          row = changed,
          issue = "common_name_standardized",
          detail = NA_character_,
          stringsAsFactors = FALSE
        )
      )
    }
    df[[col]] <- x
  }

  list(data = df, issues = issues)
}

#' Correct known typos in the interaction column using a lookup table
#' @param df harmonized data frame
#' @param corrections data frame with columns "incorrect" and "correct"
#' @returns list(data = cleaned df, issues = issues log)
correct_known_typos <- function(df, corrections) {
  issues <- empty_issues_log()
  if (!"interaction" %in% names(df)) {
    return(list(data = df, issues = issues))
  }

  original <- df$interaction
  lookup_key <- tolower(trimws(original))
  match_idx <- match(lookup_key, tolower(trimws(corrections$incorrect)))
  has_correction <- !is.na(match_idx)

  cleaned <- original
  cleaned[has_correction] <- corrections$correct[match_idx[has_correction]]

  changed <- which(has_correction)
  if (length(changed)) {
    issues <- rbind(
      issues,
      data.frame(
        source_file = df$source_file[changed],
        column = "interaction",
        row = changed,
        issue = "typo_corrected",
        detail = original[changed],
        stringsAsFactors = FALSE
      )
    )
  }
  df$interaction <- cleaned

  list(data = df, issues = issues)
}

#' Flag rows where source_url_backfilled was set during harmonization
#'
#' aux_harmonize_datasheet_versions.R's reshape_sources() backfills a blank
#' sourceB/C/D_URL from sourceA_URL when the paired notes column has
#' content but the URL doesn't. That substitution is data-affecting, so it
#' gets logged here into the audit trail rather than passing through
#' silently. The helper column itself is dropped from `data` afterward --
#' it's bookkeeping for the audit, not part of the output schema.
#' @param df harmonized data frame (must have a source_url_backfilled
#'   logical column if reshape_sources() was used upstream; a no-op
#'   otherwise)
#' @returns list(data = df with source_url_backfilled column removed,
#'   issues = issues log)
flag_backfilled_urls <- function(df) {
  issues <- empty_issues_log()
  if (!"source_url_backfilled" %in% names(df)) {
    return(list(data = df, issues = issues))
  }

  backfilled <- which(df$source_url_backfilled)
  if (length(backfilled)) {
    issues <- rbind(
      issues,
      data.frame(
        source_file = df$source_file[backfilled],
        column = "source_URL",
        row = backfilled,
        issue = "source_url_backfilled_from_sourceA",
        detail = NA_character_,
        stringsAsFactors = FALSE
      )
    )
  }
  df$source_url_backfilled <- NULL

  list(data = df, issues = issues)
}

#' Flag implausible latitude/longitude values
#'
#' Runs BEFORE coerce_col_types(), while values are still the original
#' strings -- DMS-formatted values need to be caught here, since after
#' numeric coercion they'd already be NA and this function would have
#' nothing left to inspect. Does not attempt to auto-convert DMS to decimal
#' degrees; flags for manual review instead.
#' @param df harmonized data frame (latitude/longitude still character)
#' @returns list(data = df unchanged, issues = issues log)
validate_latlon <- function(df) {
  issues <- empty_issues_log()
  dms_pattern <- "[\u00b0'\"]|\\bN\\b|\\bS\\b|\\bE\\b|\\bW\\b"

  check_one <- function(col, bound) {
    if (!col %in% names(df)) {
      return(invisible(NULL))
    }
    vals <- trimws(df[[col]])
    non_na <- !is.na(vals)

    looks_dms <- non_na & grepl(dms_pattern, vals)
    if (any(looks_dms)) {
      rows <- which(looks_dms)
      issues <<- rbind(
        issues,
        data.frame(
          source_file = df$source_file[rows],
          column = col,
          row = rows,
          issue = "latlon_looks_like_dms_not_decimal",
          detail = vals[rows],
          stringsAsFactors = FALSE
        )
      )
    }

    numeric_vals <- suppressWarnings(as.numeric(vals))
    not_numeric <- non_na & !looks_dms & is.na(numeric_vals)
    if (any(not_numeric)) {
      rows <- which(not_numeric)
      issues <<- rbind(
        issues,
        data.frame(
          source_file = df$source_file[rows],
          column = col,
          row = rows,
          issue = "latlon_not_numeric",
          detail = vals[rows],
          stringsAsFactors = FALSE
        )
      )
    }

    out_of_range <- non_na &
      !is.na(numeric_vals) &
      (numeric_vals < -bound | numeric_vals > bound)
    if (any(out_of_range)) {
      rows <- which(out_of_range)
      issues <<- rbind(
        issues,
        data.frame(
          source_file = df$source_file[rows],
          column = col,
          row = rows,
          issue = "latlon_out_of_range",
          detail = vals[rows],
          stringsAsFactors = FALSE
        )
      )
    }
  }

  check_one("latitude", 90)
  check_one("longitude", 180)

  list(data = df, issues = issues)
}

#' Coerce every schema column to its declared data_format
#'
#' Runs LAST among the cleaning steps, after commas are stripped and lat/
#' long DMS values are already flagged. For numeric/integer columns, any
#' value that had real content but fails to parse is logged (with the
#' original value in `detail`) rather than silently becoming NA -- that
#' logged NA is exactly what check_mandatory_fields() picks up next if the
#' column happens to be mandatory.
#' @param df harmonized data frame
#' @param schema data frame from column_names.csv (columns: column_name,
#'   data_format, ...)
#' @returns list(data = type-coerced df, issues = issues log)
coerce_col_types <- function(df, schema) {
  issues <- empty_issues_log()

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
      lost <- !is.na(original) & is.na(converted)
      if (any(lost)) {
        rows <- which(lost)
        issues <- rbind(
          issues,
          data.frame(
            source_file = df$source_file[rows],
            column = col,
            row = rows,
            issue = "type_coercion_failed",
            detail = original[rows],
            stringsAsFactors = FALSE
          )
        )
      }
    }

    df[[col]] <- converted
  }

  list(data = df, issues = issues)
}

# ============================================================================
# MANDATORY FIELD AUDIT
# ============================================================================

#' Flag rows with a blank mandatory field
#'
#' Checks whatever is NA at this point in the pipeline -- whether it was
#' originally blank in the raw data, or became NA via a failed type
#' coercion above. Both are equally "missing" from an ERROR standpoint.
#' @param df cleaned + type-coerced data frame
#' @param mandatory_cols character vector of column names flagged
#'   mandatory_col == "x" in column_names.csv
#' @returns issues log (no `data` element -- this function doesn't modify df)
check_mandatory_fields <- function(df, mandatory_cols) {
  issues <- empty_issues_log()
  cols <- intersect(mandatory_cols, names(df))

  for (col in cols) {
    missing <- is.na(df[[col]])
    if (any(missing)) {
      rows <- which(missing)
      issues <- rbind(
        issues,
        data.frame(
          source_file = df$source_file[rows],
          column = col,
          row = rows,
          issue = "missing_mandatory_field",
          detail = NA_character_,
          stringsAsFactors = FALSE
        )
      )
    }
  }

  issues
}

# ============================================================================
# AUDIT REPORT (wide, one row per file) + OUTPUT WRITING
# ============================================================================

#' Summarize which rows were excluded for missing mandatory fields, per file
#'
#' Produces one row per affected source_file with a count of excluded rows
#' and a human-readable detail string listing each excluded row and which
#' mandatory column(s) were missing on it, e.g. "row 45: taxa1_scientific;
#' row 112: interaction, effect_tx2_on_tx1". Row numbers refer to the
#' position in the harmonized data frame at the time this audit ran, not
#' the original raw CSV's line number.
#' @param mandatory_issues subset of the issues log where
#'   issue == "missing_mandatory_field"
#' @returns data frame: source_file, n_rows_excluded_error,
#'   excluded_rows_detail
summarize_excluded_rows <- function(mandatory_issues) {
  if (nrow(mandatory_issues) == 0) {
    return(data.frame(
      source_file = character(),
      n_rows_excluded_error = integer(),
      excluded_rows_detail = character(),
      stringsAsFactors = FALSE
    ))
  }

  per_row <- aggregate(
    column ~ source_file + row,
    data = mandatory_issues,
    FUN = function(x) paste(unique(x), collapse = ", ")
  )

  per_file <- do.call(
    rbind,
    lapply(split(per_row, per_row$source_file), function(d) {
      d <- d[order(d$row), ]
      data.frame(
        source_file = unique(d$source_file),
        n_rows_excluded_error = nrow(d),
        excluded_rows_detail = paste0(
          "row ",
          d$row,
          ": ",
          d$column,
          collapse = "; "
        ),
        stringsAsFactors = FALSE
      )
    })
  )
  rownames(per_file) <- NULL
  per_file
}

#' Build the wide-format, one-row-per-file audit report
#'
#' status is ERROR if the file has any missing_mandatory_field issue,
#' WARNING if it has any other issue but no ERROR, OK otherwise. Note that
#' ERROR here means "this file had at least one row excluded" -- exclusion
#' itself is row-level (see write_clean_audit_outputs()), not file-level,
#' so an ERROR file can still contribute its non-excluded rows to the
#' cleaned output. n_rows_excluded_error and excluded_rows_detail make
#' that row-level detail visible per file rather than collapsing it into a
#' single ERROR flag. A flag_<column> column is added for every column
#' that had at least one issue anywhere in the data, with a count of
#' affected rows for that file.
#' @param df cleaned + type-coerced data frame (for row counts)
#' @param all_issues combined issues log from every cleaning step
#'   (including check_mandatory_fields())
#' @returns data frame, one row per source_file
build_audit_report <- function(df, all_issues) {
  file_list <- unique(df$source_file)
  n_rows <- as.data.frame(table(df$source_file), stringsAsFactors = FALSE)
  names(n_rows) <- c("source_file", "n_rows")

  if (nrow(all_issues) == 0) {
    flags <- data.frame(source_file = file_list, stringsAsFactors = FALSE)
  } else {
    tab <- table(all_issues$source_file, paste0("flag_", all_issues$column))
    flags <- as.data.frame.matrix(tab)
    flags$source_file <- rownames(flags)
    rownames(flags) <- NULL

    missing_files <- setdiff(file_list, flags$source_file)
    if (length(missing_files)) {
      filler <- as.data.frame(matrix(
        0,
        nrow = length(missing_files),
        ncol = ncol(flags) - 1,
        dimnames = list(NULL, setdiff(names(flags), "source_file"))
      ))
      filler$source_file <- missing_files
      flags <- rbind(flags, filler)
    }
  }

  mandatory_issues <- all_issues[
    all_issues$issue == "missing_mandatory_field",
  ]
  error_files <- unique(mandatory_issues$source_file)
  warning_files <- unique(all_issues$source_file)

  base <- data.frame(source_file = file_list, stringsAsFactors = FALSE)
  base$status <- ifelse(
    base$source_file %in% error_files,
    "ERROR",
    ifelse(base$source_file %in% warning_files, "WARNING", "OK")
  )
  base$issue_summary <- vapply(
    base$source_file,
    function(f) {
      f_issues <- unique(all_issues$issue[all_issues$source_file == f])
      paste(f_issues, collapse = "; ")
    },
    character(1)
  )

  excluded_detail <- summarize_excluded_rows(mandatory_issues)

  report <- merge(base, n_rows, by = "source_file", all.x = TRUE)
  report <- merge(report, excluded_detail, by = "source_file", all.x = TRUE)
  report$n_rows_excluded_error[is.na(report$n_rows_excluded_error)] <- 0L
  report$excluded_rows_detail[is.na(report$excluded_rows_detail)] <- ""
  report <- merge(report, flags, by = "source_file", all.x = TRUE)

  status_order <- match(report$status, c("ERROR", "WARNING", "OK"))
  report <- report[order(status_order, report$source_file), ]

  front_cols <- c(
    "source_file",
    "n_rows",
    "status",
    "issue_summary",
    "n_rows_excluded_error",
    "excluded_rows_detail"
  )
  report[, c(front_cols, setdiff(names(report), front_cols))]
}

#' Exclude rows missing a mandatory field and write the two output CSVs
#'
#' Exclusion is ROW-level, not file-level: only the specific rows flagged
#' missing_mandatory_field are dropped from the cleaned output. A file with
#' one bad row still contributes its other, valid rows -- the file's
#' ERROR status in the report (see build_audit_report()) flags that it had
#' exclusions, without discarding data that was actually fine.
#' @param df cleaned + type-coerced data frame
#' @param all_issues combined issues log from every cleaning step
#'   (including check_mandatory_fields())
#' @param report audit report from build_audit_report()
#' @param cleaned_output_path file path to write the cleaned csv to
#' @param audit_report_path file path to write the audit report csv to
#' @returns invisibly, the cleaned data frame that was written
write_clean_audit_outputs <- function(
  df,
  all_issues,
  report,
  cleaned_output_path,
  audit_report_path
) {
  excluded_rows <- unique(all_issues$row[
    all_issues$issue == "missing_mandatory_field"
  ])
  cleaned_df <- if (length(excluded_rows)) df[-excluded_rows, ] else df

  write.csv(
    cleaned_df,
    cleaned_output_path,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )
  write.csv(
    report,
    audit_report_path,
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )

  invisible(cleaned_df)
}

# ============================================================================
# DRIVER
# ============================================================================

#' Run the full clean + audit stage on the harmonized data frame
#' @param df harmonized data frame (from aux_harmonize_datasheet_versions.R)
#' @param schema_path path to column_names.csv
#' @param corrections_path path to aux_interaction_corrections.csv
#' @param cleaned_output_path file path to write the cleaned csv to
#' @param audit_report_path file path to write the audit report csv to
#' @returns list(data = final cleaned df, issues = full issues log,
#'   report = audit report)
run_clean_and_audit <- function(
  df,
  schema_path,
  corrections_path,
  cleaned_output_path,
  audit_report_path
) {
  schema <- read.csv(schema_path, stringsAsFactors = FALSE)
  schema <- schema[!is.na(schema$column_name), ]

  mandatory_cols <- schema$column_name[
    !is.na(schema$mandatory_col) & schema$mandatory_col == "x"
  ]
  numeric_cols <- schema$column_name[
    schema$data_format %in% c("numeric", "integer")
  ]

  corrections <- read.csv(corrections_path, stringsAsFactors = FALSE)

  r1 <- clean_collapse_spaces(df)
  r2 <- clean_numeric_commas(r1$data, numeric_cols)
  r3 <- standardize_taxon_names(r2$data)
  r4 <- correct_known_typos(r3$data, corrections)
  r5 <- flag_backfilled_urls(r4$data)
  r6 <- validate_latlon(r5$data)
  r7 <- coerce_col_types(r6$data, schema)
  mandatory_issues <- check_mandatory_fields(r7$data, mandatory_cols)

  all_issues <- do.call(
    rbind,
    list(
      r1$issues,
      r2$issues,
      r3$issues,
      r4$issues,
      r5$issues,
      r6$issues,
      r7$issues,
      mandatory_issues
    )
  )

  report <- build_audit_report(r7$data, all_issues)
  cleaned <- write_clean_audit_outputs(
    r7$data,
    all_issues,
    report,
    cleaned_output_path,
    audit_report_path
  )

  list(data = cleaned, issues = all_issues, report = report)
}

result <- run_clean_and_audit(
  df,
  schema_path = schema_path,
  corrections_path = corrections_path,
  cleaned_output_path = cleaned_output_path,
  audit_report_path = audit_report_path
)
df_clean <- result$data
audit <- result$report
