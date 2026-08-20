# TITLE:            [FILL IN]
# PROJECT:          [FILL IN]
# AUTHORS:          [FILL IN]
# COLLABORATORS:    [FILL IN]
# DATA INPUT:       CSV files listed in aux_files_with_schema.csv (path: ./R/auxiliary_scripts/aux_files_with_schema.csv),
#                    grouped by schema_name (schema_1 through schema_9); each group represents a distinct
#                    historical version of the data sheet schema
# DATA OUTPUT:      s_7_9_8_6_4_1_5_2 -- a single harmonized data frame combining all schema versions
#                    (schema_1, 2, 4, 5, 6, 7, 8, 9) into one consistent column structure
# DATE:             [FILL IN]
# OVERVIEW:         Reads in raw data files grouped by their schema version, then progressively
#                    harmonizes them into a single unified schema by renaming, reshaping, concatenating,
#                    and dropping columns as each older/newer schema version is merged in
# REQUIRES:         [FILL IN]
# NOTES:            [FILL IN]

# Harmonize data sheet versions

library(tidyverse)
library(googlesheets4)

gs4_auth(scopes = "https://www.googleapis.com/auth/spreadsheets.readonly")

file_info_path <- "./R/auxiliary_scripts/aux_files_with_schema.csv"
file_info <- read.csv(file_info_path)


sheet_id <- "https://docs.google.com/spreadsheets/d/16CqFzM9VNISBAy9LfZeQPTMWOAuMHOjPc2NSwquErw8/edit?gid=1151304040#gid=1151304040"

sheet_meta <- gs4_get(sheet_id)
tab_names <- sheet_meta$sheets$name

all_tabs <- purrr::map(
  rlang::set_names(tab_names),
  ~ read_sheet(sheet_id, sheet = .x)
)

walk2(
  all_tabs,
  names(all_tabs),
  ~ write_csv(
    .x,
    file.path("./docs/interaction_metadata_schemas", paste0(.y, ".csv"))
  )
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Load all files belonging to a given schema group and row-bind them into
# a single data frame, tagging each row with its source file name
load_schema <- function(df, schema_num) {
  temp <- df |> dplyr::filter(schema_name == schema_num)
  do.call(
    rbind,
    lapply(temp$file, function(f) {
      read.csv(f) |> dplyr::mutate(source_file = basename(f))
    })
  )
}

# Collapse several old columns into one new column per row, keeping only
# unique, non-blank values and joining them with "; "; drops the old columns
# (except when old_cols and new_col overlap)
concatenate_cols <- function(df, old_cols, new_col) {
  df |>
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

# Reshape a wide data frame with multiple paired source-URL/notes columns
# into a long format with one source_URL / text_excerpt pair per row,
# dropping rows where both the URL and notes are empty; preserves original
# row order via a temporary .orig_row index.
#
# BACKFILL: if a later source's URL column (e.g. sourceB_URL) is blank but
# its paired notes column (e.g. notesB) has content, the URL is backfilled
# from the FIRST url column (url_cols[1], e.g. sourceA_URL) -- this covers
# entries where the same source was cited multiple times but the URL was
# only typed once, in sourceA. Ported over from sources_wide_to_long() in
# shared_functions.R, which had this logic but wasn't being used anywhere
# in the schema-harmonization pipeline.
# Backfilled rows are tagged source_url_backfilled = TRUE (rather than
# silently substituting the value) so the downstream audit script can flag
# and report on them instead of letting the substitution pass unnoticed.
reshape_sources <- function(df, url_cols, notes_cols, id_cols = NULL) {
  stopifnot(length(url_cols) == length(notes_cols))

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

    out$source_URL <- ifelse(has_content(u_keep), u_keep, NA)
    out$text_excerpt <- ifelse(has_content(n_keep), n_keep, NA)
    out$source_url_backfilled <- backfilled
    out$.orig_row <- df$.orig_row[keep]
    out
  })

  result <- do.call(rbind, pieces)
  result <- result[order(result$.orig_row), ]
  result$.orig_row <- NULL
  rownames(result) <- NULL
  result
}
############################################################################################

# ============================================================================
# SCHEMA HARMONIZATION PIPELINE
# Each step loads the next schema version, applies whatever renaming/column
# additions are needed to align it with the schemas already merged, then
# row-binds it in. Naming convention: s_<schemas included, most-recent-first>
# ============================================================================

# --- Merge schema_2 into base (add placeholder name_changes column) ---
s_2 <- load_schema(file_info, "schema_2") |>
  mutate(name_changes = NA) |>
  clean_na()

# --- Merge schema_5 with schema_2 (add placeholder other_species1 column) ---
s_5_2 <- load_schema(file_info, "schema_5") |>
  rbind(s_2) |>
  mutate(other_species1 = NA) |>
  clean_na()

# --- Merge schema_1 with (schema_5, schema_2); tag version, add DatabaseSearchURL placeholder ---
s_1_5_2 <- load_schema(file_info, "schema_1") |>
  rbind(s_5_2) |>
  # mutate(version = "v1", DatabaseSearchURL = "not_evaluated") |>
  mutate(version = "v1", DatabaseSearchURL = NA) |>
  clean_na()

# --- Merge schema_4 with (schema_1, 5, 2); tag as version v2 ---
s_4_1_5_2 <- load_schema(file_info, "schema_4") |>
  mutate(version = "v2") |>
  rbind(s_1_5_2) |>
  clean_na()

OLDsource_cols <- c("OLDsourceA", "OLDsourceB")

# --- Merge schema_6 with (schema_4, 1, 5, 2); rename source columns and
#     collapse old source columns into sourceA_URL ---
s_6_4_1_5_2 <- load_schema(file_info, "schema_6") |>
  mutate(version = "v2") |>
  rename(DatabaseSearchURL = GoogleScholarURL) |>
  rbind(s_4_1_5_2) |>
  rename(
    sourceA_URL = sourceAupdatedURL,
    sourceB_URL = sourceBupdatedURL,
    sourceC_URL = sourceCupdatedURL,
    sourceD_URL = sourceDupdatedURL
  ) |>
  concatenate_cols(OLDsource_cols, "Oldsource") |>
  concatenate_cols(c("Oldsource", "sourceA_URL"), "sourceA_URL") |>
  clean_na()

url_cols <- c("sourceA_URL", "sourceB_URL", "sourceC_URL", "sourceD_URL")
notes_cols <- c("notesA", "notesB", "notesC", "notesD")

# --- Merge schema_8 with (schema_6, 4, 1, 5, 2); reshape paired source/notes
#     columns into long format; rename breeding_migration; add evaluation
#     placeholder columns ---
s_8_6_4_1_5_2 <- load_schema(file_info, "schema_8") |>
  mutate(version = "v2") |>
  rbind(s_6_4_1_5_2) |>
  reshape_sources(url_cols, notes_cols) |>
  rename(breeding_migration = nonbreedingseason) |>
  # mutate(
  #   interaction_strength = "not_evaluated",
  #   time_of_year = "not_evaluated",
  #   source_citation = "not_evaluated",
  #   species1_lifestage = "not_evaluated",
  #   species2_lifestage = "not_evaluated"
  # ) |>
  mutate(
    interaction_strength = NA,
    time_of_year = NA,
    source_citation = NA,
    species1_lifestage = NA,
    species2_lifestage = NA
  ) |>
  clean_na()

# --- Merge schema_9 with (schema_8, 6, 4, 1, 5, 2); tag as version v3; rename
#     to taxa1/taxa2 naming convention; add placeholder columns; drop
#     other_species1 (no longer needed) ---
s_9_8_6_4_1_5_2 <- load_schema(file_info, "schema_9") |>
  mutate(
    version = "v3",
    # n_studies = "not_evaluated",
    # BOW_evidence = "not_evaluated"
    n_studies = NA,
    BOW_evidence = NA,
    source_url_backfilled = NA
  ) |>
  rename(source_citation = Citation) |>
  rbind(s_8_6_4_1_5_2) |>
  rename(
    effect_tx1_on_tx2 = effect_sp1_on_sp2,
    effect_tx2_on_tx1 = effect_sp2_on_sp1,
    taxa1_common = species1_common,
    taxa2_common = species2_common,
    taxa1_scientific = species1_scientific,
    taxa2_scientific = species2_scientific,
    taxa1_lifestage = species1_lifestage,
    taxa2_lifestage = species2_lifestage,
    interaction_excerpt = text_excerpt
  ) |>
  # mutate(
  #   tx1_life_history_season = "not_evaluated",
  #   tx2_life_history_season = "not_evaluated",
  #   country = "not_evaluated",
  #   location = "not_evaluated",
  #   timing_location_excerpt = "not_evaluated",
  #   year = "not_evaluated",
  # ) |>
  mutate(
    tx1_life_history_season = NA,
    tx2_life_history_season = NA,
    country = NA,
    location = NA,
    timing_location_excerpt = NA,
    year = NA,
  ) |>
  dplyr::select(-other_species1) |>
  clean_na()

# --- Merge schema_7 with (schema_9, 8, 6, 4, 1, 5, 2); tag as version v4;
#     final step -- drop columns that are no longer part of the unified
#     schema (BOW_evidence, n_studies, name_changes, DatabaseSearchURL,
#     breeding_migration) ---
s_7_9_8_6_4_1_5_2 <- load_schema(file_info, "schema_7") |>
  mutate(
    version = "v4",
    # n_studies = "not_evaluated",
    # BOW_evidence = "not_evaluated",
    # breeding_migration = "not_evaluated"
    n_studies = NA,
    BOW_evidence = NA,
    breeding_migration = NA,
    source_url_backfilled = NA
  ) |>
  rbind(s_9_8_6_4_1_5_2) |>
  dplyr::select(
    -BOW_evidence,
    -n_studies,
    -name_changes,
    -DatabaseSearchURL,
    -breeding_migration
  ) |>
  mutate(taxa1_group = "bird", taxa2_group = "bird") |>
  clean_na()

df <- s_7_9_8_6_4_1_5_2
