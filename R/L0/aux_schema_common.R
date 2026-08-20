## =============================================================================
## aux_schema_common.R
## Shared setup for the schema-audit tooling. Sourced by:
##   - aux_schema_audit.R      (read-only: NEVER assigns schema numbers)
##   - aux_schema_register.R   (the ONLY script that assigns/appends numbers)
## Nothing in here writes files; it just prepares data and defines helpers.
## =============================================================================

`%||%` <- function(x, y) if (is.null(x)) y else x

## ---- config ----------------------------------------------------------------
root_dir <- "C:/Users/kelly/OneDrive - Michigan State University/Research/AvianMetaNetwork/AvianMetaNetwork-Working/L0/species/"
in_review_dir <- "C:/Users/kelly/OneDrive - Michigan State University/Research/AvianMetaNetwork/AvianMetaNetwork-Working/L0/species_in_review/"

ignore_column_order <- TRUE

schema_sep <- " | " # separator used to serialise a column set into one string

## Output / state file paths.
## schema_key_path is read by BOTH scripts and is the frozen source of truth
## for schema numbering.
presence_path <- "./R/auxiliary_scripts/aux_schema_cols.csv"
schema_key_path <- "./R/auxiliary_scripts/aux_schema_metadata.csv"
file_info_path <- "./R/auxiliary_scripts/aux_files_with_schema.csv"

## ---- discover CSVs ---------------------------------------------------------
spp_files <- list.files(
  root_dir,
  pattern = "\\.csv$",
  recursive = TRUE,
  full.names = TRUE
)
rev_files <- list.files(
  in_review_dir,
  pattern = "\\.csv$",
  recursive = TRUE,
  full.names = TRUE
)
csv_files <- c(spp_files, rev_files)

get_cols <- function(f) {
  x <- tryCatch(
    names(read.csv(f, nrows = 0, check.names = FALSE)),
    error = function(e) NA
  )
  if (length(x) == 1 && is.na(x)) {
    return(NA)
  }
  if (ignore_column_order) {
    x <- sort(x)
  }
  x
}

## ---- git: latest commit date per file (both dirs, assumed one repo) --------
repo_root <- system2(
  "git",
  c("-C", shQuote(root_dir), "rev-parse", "--show-toplevel"),
  stdout = TRUE
)
repo_root <- normalizePath(repo_root[1], winslash = "/", mustWork = TRUE)

# repo-relative path for a directory (forward slashes, matching git's output)
to_rel <- function(d) {
  sub(
    paste0("^", repo_root, "/?"),
    "",
    normalizePath(d, winslash = "/", mustWork = FALSE)
  )
}
root_rel <- to_rel(root_dir)
review_rel <- to_rel(in_review_dir)

# one git log over both pathspecs; @@@ lines carry the commit date, the lines
# in between are the files changed in that commit (restricted to our pathspecs)
git_out <- system2(
  "git",
  c(
    "-C",
    shQuote(repo_root),
    "log",
    "--name-only",
    "--format=@@@%cI",
    "--",
    root_rel,
    review_rel
  ),
  stdout = TRUE
)

latest_commit_map <- list()
current_date <- NA_character_
for (line in git_out) {
  if (startsWith(line, "@@@")) {
    current_date <- sub("^@@@", "", line)
  } else if (nzchar(line) && !line %in% names(latest_commit_map)) {
    # first time we see a file = its most recent commit (git log is newest-first)
    latest_commit_map[[line]] <- current_date
  }
}

## ---- per-file schema + commit info -----------------------------------------
file_info <- do.call(
  rbind,
  lapply(seq_along(csv_files), function(i) {
    cols <- get_cols(csv_files[i])
    data.frame(
      file = csv_files[i],
      schema = if (all(is.na(cols))) NA else paste(cols, collapse = schema_sep),
      ncols = if (all(is.na(cols))) NA else length(cols),
      latest_commit = latest_commit_map[[to_rel(csv_files[i])]] %||%
        NA_character_,
      stringsAsFactors = FALSE
    )
  })
)

file_info$latest_commit <- lubridate::ymd_hms(
  file_info$latest_commit,
  tz = "UTC"
)

valid <- subset(file_info, !is.na(schema))

## ---- helpers shared by audit + register ------------------------------------

# Read the frozen key and return a named vector: schema string -> schema_name.
# Returns NULL if the key file does not exist yet (i.e. first-time bootstrap).
read_schema_map <- function() {
  if (!file.exists(schema_key_path)) {
    return(NULL)
  }
  key <- read.csv(
    schema_key_path,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (nrow(key) == 0) {
    return(NULL)
  }
  setNames(key$schema_name, key$schema)
}

# integer suffix of "schema_12" -> 12L (used to find the next free number)
schema_number <- function(nm) as.integer(sub("^schema_", "", nm))

# Build the schema key data.frame from `valid` and a frozen schema map.
# Numbering + schema strings come ENTIRELY from `schema_map`; the descriptive
# columns (file_count, commit range, example_file) are recomputed from the
# current data so the key stays current without ever renumbering.
build_schema_key <- function(valid, schema_map) {
  valid$schema_name <- schema_map[valid$schema]
  ordered_names <- unname(schema_map)[order(schema_number(unname(schema_map)))]

  key <- do.call(
    rbind,
    lapply(ordered_names, function(nm) {
      d <- valid[!is.na(valid$schema_name) & valid$schema_name == nm, ]
      dates <- d$latest_commit[!is.na(d$latest_commit)]
      schema_str <- names(schema_map)[schema_map == nm][1]
      data.frame(
        schema_name = nm,
        file_count = nrow(d),
        ncols = if (nrow(d)) {
          d$ncols[1]
        } else {
          length(strsplit(schema_str, schema_sep, fixed = TRUE)[[1]])
        },
        earliest_latest_commit = if (length(dates)) {
          min(dates)
        } else {
          as.POSIXct(NA)
        },
        latest_latest_commit = if (length(dates)) {
          max(dates)
        } else {
          as.POSIXct(NA)
        },
        example_file = if (nrow(d)) d$file[1] else NA_character_,
        schema = schema_str,
        stringsAsFactors = FALSE
      )
    })
  )
  row.names(key) <- NULL
  key
}

# Presence/absence matrix (rows = unique columns, cols = schemas) for the
# schemas in `schema_map`, ordered by schema number.
build_presence <- function(schema_map) {
  ord <- order(schema_number(unname(schema_map)))
  schema_levels <- names(schema_map)[ord]
  schema_names <- unname(schema_map)[ord]

  schema_cols <- lapply(schema_levels, function(s) {
    strsplit(s, schema_sep, fixed = TRUE)[[1]]
  })
  names(schema_cols) <- schema_names

  all_cols <- sort(unique(unlist(schema_cols)))

  presence <- vapply(
    schema_cols,
    function(cols) all_cols %in% cols,
    logical(length(all_cols))
  )
  if (is.null(dim(presence))) {
    # guard: single column or single schema
    presence <- matrix(
      presence,
      nrow = length(all_cols),
      dimnames = list(NULL, schema_names)
    )
  }
  data.frame(
    column = all_cols,
    presence,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}
