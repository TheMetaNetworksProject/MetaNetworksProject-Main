# TITLE:            Interaction column cleaning functions
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:    Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas, Minyoung Lee, Patrick Bills
# DATA INPUT:       interactions.csv (list of permitted interaction types),
#                   read once when this script is sourced. Every function takes
#                   the harmonized data frame `df` (from
#                   2_harmonize_datasheet_versions.R) plus whatever else it
#                   needs as explicit arguments.
# DATA OUTPUT:      None. Every function returns `df` with notes appended to
#                   the `errors` and/or `warnings` columns.
# DATE:             initiated: 7 October 2026
# OVERVIEW:         Cleans and validates the `interaction` column:
#                     1. correct_known_typos()     swaps known typos for their
#                                                  fixes (lookup table)
#                     2. standardize_interactions() lowercases, then checks
#                                                  every value against the
#                                                  permitted interaction list
#
#                   Shared contract for every function here (and for the
#                   column-specific cleaners in clean_data_<column>.R):
#                     - takes `df`, returns `df` (same rows, same order)
#                     - never drops rows
#                     - notes go in `errors` / `warnings`, joined with "; "
#                     - routine fixes are always logged as warnings
#                     - values that can't be fixed are logged as an error if
#                       the column is mandatory, otherwise as a warning
# REQUIRES:         dplyr, stringr; add_note() and append_note() from
#                   clean_data_basic.R (source that first)
# NOTES:            Row numbers in notes are not used; the note lives on the
#                   row it describes.

library(dplyr)
library(stringr)

# ============================================================================
# PERMITTED INTERACTIONS
# ============================================================================

# Read once at source time; standardize_interactions() checks against this.
permitted_interactions <- read.csv(
  "./docs/interaction_metadata_schemas/interactions.csv"
) |>
  distinct(interaction) |>
  filter(!is.na(interaction))

# ============================================================================
# STEP 1: KNOWN TYPOS
# ============================================================================

#' Correct known typos in the interaction column using a lookup table
#'
#' Matching ignores case and leading/trailing whitespace. Each corrected value
#' is logged as a warning with the original value.
#' @param df harmonized data frame
#' @param corrections data frame with columns "incorrect" and "correct"
#' @returns df
correct_known_typos <- function(df, corrections) {
  if (!"interaction" %in% names(df)) {
    return(df)
  }

  # find rows whose (normalized) value is a known typo
  original <- df$interaction
  match_idx <- match(
    tolower(trimws(original)),
    tolower(trimws(corrections$incorrect))
  )
  rows <- which(!is.na(match_idx))

  # apply the fix, then log it with the original value
  df$interaction[rows] <- corrections$correct[match_idx[rows]]
  add_note(
    df,
    rows,
    paste0("interaction: typo corrected from '", original[rows], "'"),
    "warning"
  )
}

#' Move "potential" / "artificial" qualifiers out of the interaction column
#'
#' Some sheets encode certainty or experimental context in the interaction
#' itself (e.g. "potential predation", "brood parasitism-artificial"). The
#' permitted interaction list doesn't allow these, so this function:
#'   - removes the word from `interaction`
#'   - records it in `interaction_confidence`: "potential" -> "weak",
#'     "artificial" -> "artificial"
#'   - logs a warning on every row it changes, with the original value
#'
#' Matching ignores case and also catches the typos seen so far
#' ("poteintal", "artifical"). Add new variants to the two patterns below.
#' If `interaction_confidence` already contains the term (as a whole word) it
#' is not added again; otherwise it is appended after "; ".
#' @param df harmonized data frame (needs `interaction` and
#'   `interaction_confidence` columns)
#' @returns df with qualifiers removed from `interaction`, terms added to
#'   `interaction_confidence`, and warnings appended to `warnings`
fix_potential_and_artificial <- function(df) {
  # ---- patterns ---------------------------------------------------------
  # regexes, matched case-insensitively
  potential_pat <- "pote(ntia|inta)l" # potential, poteintal
  artificial_pat <- "artific(i)?al" # artificial, artifical

  # ---- find affected rows -----------------------------------------------
  # NA interactions are treated as "no match" (handled elsewhere)
  has_potential <- coalesce(
    str_detect(df$interaction, regex(potential_pat, ignore_case = TRUE)),
    FALSE
  )
  has_artificial <- coalesce(
    str_detect(df$interaction, regex(artificial_pat, ignore_case = TRUE)),
    FALSE
  )
  original <- df$interaction # kept for the warning message

  # ---- update interaction_confidence --------------------------------------
  # Append `term` for the flagged `rows`, unless it is already in the column.
  # Empty cells get just the term; non-empty cells get "<existing>; <term>".
  add_term <- function(existing, term, rows) {
    already <- coalesce(
      str_detect(existing, paste0("\\b", term, "\\b")),
      FALSE
    )
    add <- rows & !already
    case_when(
      add & is.na(existing) ~ term,
      add ~ paste(existing, term, sep = "; "),
      TRUE ~ existing
    )
  }
  df$interaction_confidence <- add_term(
    df$interaction_confidence,
    "weak",
    has_potential
  )
  df$interaction_confidence <- add_term(
    df$interaction_confidence,
    "artificial",
    has_artificial
  )

  # ---- clean the interaction column ---------------------------------------
  # Remove the words, collapse leftover spaces, and trim stray hyphens/spaces
  # (e.g. "brood parasitism-artificial" -> "brood parasitism")
  df$interaction <- df$interaction |>
    str_remove_all(regex(potential_pat, ignore_case = TRUE)) |>
    str_remove_all(regex(artificial_pat, ignore_case = TRUE)) |>
    str_replace_all("\\s+", " ") |>
    str_remove_all("^[\\s-]+|[\\s-]+$")

  # ---- log changes ----------------------------------------------------------
  # Routine fixes are always warnings (see contract in the script header)
  rows <- which(has_potential | has_artificial)
  add_note(
    df,
    rows,
    paste0(
      "interaction: '",
      original[rows],
      "' split into interaction + interaction_confidence"
    ),
    "warning"
  )
}

# ============================================================================
# STEP 2: STANDARDIZE AND VALIDATE
# ============================================================================

#' Standardize the interaction column and check it against permitted values
#'
#' Order matters: typos are fixed first (and logged), then values are
#' lowercased, then anything not in `permitted_interactions` is logged.
#' Unrecognized values are logged as an error if the interaction column is
#' mandatory, otherwise as a warning (pass `on_invalid_for("interaction",
#' mandatory_cols)`). NA values count as unrecognized, so any NA still here
#' is flagged.
#' @param df harmonized data frame
#' @param on_invalid "error" or "warning" (see contract in header)
#' @param corrections data frame with columns "incorrect" and "correct"
#' @returns df
standardize_interactions <- function(
  df,
  on_invalid = c("error", "warning"),
  corrections
) {
  on_invalid <- match.arg(on_invalid)

  # 1. swap out typos with the known fixes (logs a warning for each one)
  df <- correct_known_typos(df, corrections)

  # 2. lowercase so case differences alone never cause a mismatch
  df$interaction <- str_to_lower(df$interaction)

  # 3. remove potential/artificial from interactions and add to interaction_confidence
  df <- fix_potential_and_artificial(df)

  # 4. flag anything that isn't a permitted interaction
  idx <- match(df$interaction, permitted_interactions$interaction)
  rows <- which(is.na(idx))

  add_note(
    df,
    rows,
    paste0(
      "interaction: '",
      df$interaction[rows],
      "' is not a recognized interaction. ",
      "Fix typo or add new interaction type to interaction metadata."
    ),
    on_invalid
  )
}


# ============================================================================
# STEP 3: CHECK TAXA EFFECTS
# ============================================================================
#' Check that effect_on_tx1 / effect_on_tx2 are -1, 0, or 1
#'
#' Does not modify values. Missing values and anything other than -1, 0, or 1
#' (including non-numeric text) are logged as errors.
#' Works whether the columns are still character or already numeric.
#' @param df harmonized data frame
#' @param cols character vector of columns to check
#' @returns df
check_effect_values <- function(
  df,
  cols = c("effect_on_tx1", "effect_on_tx2")
) {
  stopifnot(all(cols %in% names(df)))
  allowed <- c(-1, 0, 1)

  for (col in cols) {
    raw <- df[[col]]
    num <- suppressWarnings(as.numeric(raw)) # non-numeric text becomes NA

    # missing
    rows <- which(is.na(raw))
    df <- add_note(
      df,
      rows,
      paste0(col, ": missing value (must be -1, 0, or 1)"),
      "error"
    )

    # present but not -1, 0, or 1 (includes text that isn't a number)
    rows <- which(!is.na(raw) & !(num %in% allowed))
    df <- add_note(
      df,
      rows,
      paste0(col, ": '", raw[rows], "' is not -1, 0, or 1"),
      "error"
    )
  }

  df
}
