## =============================================================================
## _flagged_files.R
## Shared helpers for flagging source files. Sourced by 1_schema_audit.R and
## clean_data.R so both write flagged_file_metadata.csv in the SAME format:
##
##   source_file | row | error
##
## One row per (file, row, error message). `row` is NA for file-level problems
## (e.g. a file that does not match any registered schema).
## =============================================================================

## ---- paths -- adjust to your folder layout ---------------------------------
taxa_source_dirs <- c(
  "../MetaNetworksProject-Working/L0/taxa_to_check",
  "../MetaNetworksProject-Working/L0/taxa_checked_raw"
)
flagged_dir <- "../MetaNetworksProject-Working/L0/taxa_flagged"
flagged_metadata_name <- "flagged_file_metadata.csv"

flagged_cols <- c("source_file", "row", "error")

#' Append rows to flagged_file_metadata.csv (creating it if needed)
#'
#' Rows already in the file (same source_file, row, and error) are not
#' duplicated, so re-running a script does not grow the file.
#' @param new_rows data frame with columns source_file, row, error
#' @param flagged_dir folder holding flagged_file_metadata.csv
#' @returns path to the csv (invisibly)
append_flagged_metadata <- function(new_rows, flagged_dir) {
  stopifnot(all(flagged_cols %in% names(new_rows)))
  dir.create(flagged_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(flagged_dir, flagged_metadata_name)

  new_rows <- new_rows[, flagged_cols]
  new_rows$source_file <- as.character(new_rows$source_file)
  new_rows$row <- as.integer(new_rows$row)
  new_rows$error <- as.character(new_rows$error)

  if (file.exists(path)) {
    existing <- read.csv(
      path,
      stringsAsFactors = FALSE,
      colClasses = c("character", "integer", "character")
    )
    stopifnot(identical(names(existing), flagged_cols))
    new_rows <- rbind(existing, new_rows)
  }

  new_rows <- unique(new_rows)
  write.csv(new_rows, path, row.names = FALSE)
  invisible(path)
}

#' Record flagged files in flagged_file_metadata.csv and move them
#'
#' Order of operations, so a failure never leaves things half-done:
#'   1. locate every file in source_dirs (stops if any is missing or duplicated;
#'      nothing is written or moved)
#'   2. append the rows to flagged_file_metadata.csv
#'   3. move the files into flagged_dir
#'
#' With move = FALSE (dry run) only step 1 happens: the files are located and
#' listed, but the metadata csv is not touched and nothing is moved.
#' @param flagged data frame with columns source_file, row, error
#' @param source_dirs folders the files might currently be in
#' @param flagged_dir destination folder (taxa_flagged)
#' @param move TRUE = write metadata and move files; FALSE = dry run
#' @returns character vector of the flagged file names (invisibly)
flag_files <- function(flagged, source_dirs, flagged_dir, move = TRUE) {
  files <- unique(basename(flagged$source_file))

  if (length(files) == 0) {
    message(
      if (move) {
        "0 file(s) added to "
      } else {
        "[dry run] 0 file(s) would be added to "
      },
      flagged_dir
    )
    return(invisible(files))
  }

  # 1. locate every file first
  from <- character(length(files))
  for (i in seq_along(files)) {
    candidates <- file.path(source_dirs, files[i])
    found <- candidates[file.exists(candidates)]
    if (length(found) != 1) {
      stop(
        length(found),
        " copies of '",
        files[i],
        "' found in source_dirs (expected exactly 1)",
        call. = FALSE
      )
    }
    from[i] <- found
  }

  # dry run: report and stop before touching anything
  if (!move) {
    message(
      "[dry run] ",
      length(files),
      " file(s) would be added to ",
      flagged_dir,
      " (nothing written or moved):\n  ",
      paste(files, collapse = "\n  ")
    )
    return(invisible(files))
  }

  # 2. record in the metadata csv
  append_flagged_metadata(flagged, flagged_dir)

  # 3. move
  for (i in seq_along(files)) {
    to <- file.path(flagged_dir, files[i])
    if (!file.copy(from[i], to, overwrite = TRUE)) {
      stop("Could not copy '", from[i], "' to '", to, "'", call. = FALSE)
    }
    file.remove(from[i])
  }

  message(length(files), " file(s) added to ", flagged_dir)
  invisible(files)
}
