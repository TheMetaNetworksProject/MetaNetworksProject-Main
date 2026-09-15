# TITLE:            Standardize recorder names and extract primary recorder
# PROJECT:          MetaNetworks Project
# AUTHORS:          Kelly
# COLLABORATORS:
# DATA INPUT:       Data frame with a `recorder` column containing raw, sometimes
#                   multi-person, sometimes-inconsistently-formatted names
#                   (e.g., "Emily Parker/India Hirschowitz", "PLZ", "Ava Foutnain")
# DATA OUTPUT:      Same data frame with two new columns: `recorder_std`
#                   (standardized full name of the PRIMARY recorder only) and
#                   `recorder_match_status` ("matched" or "unmatched_manual_review")
# DATE:             initiated: 2026-08-28
# OVERVIEW:         Splits multi-recorder strings on common separators (/, ;, ,),
#                   keeps only the first (primary) recorder, trims whitespace, and
#                   maps known name variants/typos/initials to a canonical full
#                   name via an explicit lookup table. Names with no confident
#                   match are left as-is and flagged for manual review rather
#                   than guessed.
# REQUIRES:         dplyr, stringr
# NOTES:            The lookup table (`build_recorder_lookup()`) was built by hand
#                   from a one-off audit of `df |> count(recorder)`. It is NOT
#                   exhaustive for future data entry - new variants/typos that
#                   show up later will fall into recorder_match_status ==
#                   "unmatched_manual_review" and should be triaged and added to
#                   the lookup table below, following the corrections-CSV pattern
#                   used elsewhere in the pipeline (build from output, don't
#                   anticipate ahead of time). "ER" has no confirmed full name
#                   and is intentionally left unmapped.

library(dplyr)
library(stringr)

# Build the raw-variant -> canonical-full-name lookup table.
# Add new confirmed variants here as they're identified during manual review.
build_recorder_lookup <- function() {
  c(
    # Emily Parker
    "Emily Parker" = "Emily Parker",

    # India Hirschowitz (case + spacing variants)
    "India Hirschowitz" = "India Hirschowitz",
    "India HIrschowitz" = "India Hirschowitz",
    "india Hirschowitz" = "India Hirschowitz",
    "IndiaHirschowitz" = "India Hirschowitz",

    # Ava Fountain (typo variant)
    "Ava Fountain" = "Ava Fountain",
    "Ava Foutnain" = "Ava Fountain",

    # Caroline Roche
    "Caroline Roche" = "Caroline Roche",

    # Giovanni DePasquale
    "Giovanni DePasquale" = "Giovanni DePasquale",

    # Sara Zonneveld
    "Sara Zonneveld" = "Sara Zonneveld",

    # Phoebe Zarnetske (initials + truncated first-name variant)
    "Phoebe Zarnetske" = "Phoebe Zarnetske",
    "PLZ" = "Phoebe Zarnetske",
    "Phoebe" = "Phoebe Zarnetske",

    # Maddie Andreatta (typo variant)
    "Maddie Andreatta" = "Maddie Andreatta",
    "Maddie Andratta" = "Maddie Andreatta",

    # Jordan Zapata
    "Jordan Zapata" = "Jordan Zapata",

    # Liz Bauer
    "Liz Bauer" = "Liz Bauer",

    # Jamie Soehl
    "Jamie Soehl" = "Jamie Soehl",

    # Vivian Smith
    "Vivian Smith" = "Vivian Smith",

    # Olive Graves
    "Olive Graves" = "Olive Graves",

    # Addison Hoddinott
    "Addison Hoddinott" = "Addison Hoddinott",

    # Jennifer Farmer
    "Jennifer Farmer" = "Jennifer Farmer",

    # Minali Bhatt
    "Minali Bhatt" = "Minali Bhatt",

    # Aidan Hammond (initials variant)
    "Aidan Hammond" = "Aidan Hammond",
    "AH" = "Aidan Hammond",

    # Lucas Mansfield
    "Lucas Mansfield" = "Lucas Mansfield",

    # Ann Joseph (initials + case variant)
    "Ann Joseph" = "Ann Joseph",
    "AJ" = "Ann Joseph",
    "Aj" = "Ann Joseph"

    # "ER" intentionally omitted - no confirmed full name identified.
    # It will fall through to unmatched_manual_review.
  )
}

# Extract the primary (first-listed) recorder from a raw, possibly
# multi-person, recorder string.
extract_primary_recorder <- function(recorder_raw) {
  # split on /, ;, or , (with optional surrounding whitespace)
  first_token <- str_split(recorder_raw, "\\s*[/;,]\\s*", simplify = FALSE) |>
    purrr::map_chr(~ .x[1])
  str_trim(first_token)
}

# Map a vector of raw primary-recorder names to standardized full names
# using an explicit lookup table. Unmatched names are returned unchanged.
standardize_recorder_names <- function(recorder_raw_primary, lookup) {
  matched <- lookup[recorder_raw_primary]
  ifelse(is.na(matched), recorder_raw_primary, unname(matched))
}

# Wrapper: takes a data frame and the name of the raw recorder column,
# returns the data frame with recorder_std and recorder_match_status added.
standardize_recorder_column <- function(df, recorder_col, lookup) {
  raw_primary <- extract_primary_recorder(df[[recorder_col]])
  std_name <- standardize_recorder_names(raw_primary, lookup)

  df |>
    mutate(
      recorder_primary_raw = raw_primary,
      recorder_std = std_name,
      recorder_match_status = if_else(
        recorder_primary_raw %in% names(lookup),
        "matched",
        "unmatched_manual_review"
      )
    )
}

# --- Example usage ---------------------------------------------------------
lookup <- build_recorder_lookup()
df_std <- standardize_recorder_column(
  df,
  recorder_col = "recorder",
  lookup = lookup
)

# Check what fell through for manual review:
df_std |>
  filter(recorder_match_status == "unmatched_manual_review") |>
  count(recorder_primary_raw, sort = TRUE)


intxns <- read.csv("./docs/interaction_metadata_schemas/interactions.csv") |>
  filter(asymmetric == "yes")


temp <- df_std |>
  filter(interaction %in% intxns$interaction) |>
  group_by(recorder_std, source_file) |>
  slice_sample(n = min(3, n()))

sampled_files <- df_std |>
  filter(interaction %in% intxns$interaction) |>
  distinct(recorder_std, source_file) |>
  group_by(recorder_std) |>
  slice(sample(seq_len(n()), size = min(3, n()))) |>
  ungroup()

temp <- df_std |>
  filter(interaction %in% intxns$interaction) |>
  semi_join(sampled_files, by = c("recorder_std", "source_file"))
