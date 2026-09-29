# TITLE:            Standardize tx1_life_history_season
# PROJECT:          MetaNetworks Project (MetaNetworksProject-Main)
# AUTHORS:          Kelly
# COLLABORATORS:
# DATA INPUT:       harmonized_df / df from aux_harmonize_datasheet_versions.R
#                   (must contain tx1_life_history_season and original_version)
# DATA OUTPUT:      Same data frame with tx1_life_history_season standardized and
#                   notes appended to `warnings` and `errors` columns
# DATE:             initiated: 2026-09-29
# OVERVIEW:         Recodes legacy season values to the current vocabulary
#                   (breeding, migration, non-breeding, year-round) and checks
#                   v4+ entries against it.
#                     - v1/v2 (was `nonbreeding_season`): yes -> non-breeding;
#                       NA -> breeding, with a warning.
#                     - v3 (was `breeding_migration`): typo/case fixes; NA left as NA.
#                     - v4+: validated only, never modified.
#                   Multiple seasons are kept as ", "-separated values in fixed
#                   order (e.g. "breeding, non-breeding"), matching the Google
#                   Drive CSV export. Legacy values separated by ";" or ","
#                   are both recoded; v4+ values must use ",".
#                   Unrecognized values are left unchanged and noted in `errors`.
# REQUIRES:         aux_harmonize_datasheet_versions.R (run first)
# NOTES:            Add new typos/variants to the lookup tables below rather than
#                   to the functions.

library(dplyr)
library(stringr)
library(purrr)
library(tidyr)
library(tibble)

# ---- Allowed values and lookup tables ---------------------------------------

season_levels <- c("breeding", "migration", "non-breeding", "year-round")
season_sep <- ", " # separator between multiple seasons in output

# v1/v2 `nonbreeding_season`: whole-value lookup (keys are lowercased/squished)
nonbreeding_legacy_lookup <- tribble(
  ~raw                       , ~value                   , ~uncertain ,
  "yes"                      , "non-breeding"           , FALSE      ,
  "possibly"                 , "non-breeding"           , TRUE       ,
  "potential"                , "non-breeding"           , TRUE       ,
  "breeding and nonbreeding" , "breeding, non-breeding" , FALSE
)

# v3 `breeding_migration`: per-token lookup (values are split on ";" or "," first)
breeding_migration_token_lookup <- tribble(
  ~token                          , ~value         , ~uncertain ,
  "breeding"                      , "breeding"     , FALSE      ,
  "breeeding"                     , "breeding"     , FALSE      ,
  "likely breeding"               , "breeding"     , TRUE       ,
  "possible breeding"             , "breeding"     , TRUE       ,
  "partically in breeding season" , "breeding"     , TRUE       ,
  "non-breeding"                  , "non-breeding" , FALSE      ,
  "nonbreeding"                   , "non-breeding" , FALSE      ,
  "nonbreedingseason"             , "non-breeding" , FALSE      ,
  "migration"                     , "migration"    , FALSE      ,
  "year-round"                    , "year-round"   , FALSE
)

# ---- Helpers ----------------------------------------------------------------

clean_key <- function(x) str_squish(str_to_lower(x))

# pattern: regex of separators to split on. Legacy: ";" or ","; v4+: "," only.
split_tokens <- function(x, pattern = "[;,]") {
  tokens <- str_trim(str_split(x, pattern)[[1]])
  tokens[tokens != ""]
}

# One-row result used by every recode/check function
season_result <- function(
  value,
  warning = NA_character_,
  error = NA_character_
) {
  tibble(.value = value, .warning = warning, .error = error)
}

unrecognized_error <- function(raw, col) {
  paste0(col, ": unrecognized value '", str_trunc(raw, 60), "'")
}

# Append a note to an existing notes column with "; " (vectorized)
append_note <- function(existing, new) {
  case_when(
    is.na(new) ~ existing,
    is.na(existing) ~ new,
    TRUE ~ paste(existing, new, sep = "; ")
  )
}

# ---- Per-value recode / check functions -------------------------------------

# v1/v2: `nonbreeding_season`
recode_nonbreeding_legacy <- function(raw, col) {
  if (is.na(raw)) {
    return(season_result(
      "breeding",
      warning = paste0(
        col,
        ": NA in v1/v2 nonbreeding_season; assumed 'breeding'"
      )
    ))
  }
  hit <- nonbreeding_legacy_lookup[
    nonbreeding_legacy_lookup$raw == clean_key(raw),
  ]
  if (nrow(hit) == 0) {
    return(season_result(raw, error = unrecognized_error(raw, col)))
  }
  warning <- if (hit$uncertain) {
    paste0(
      col,
      ": '",
      raw,
      "' recoded to '",
      hit$value,
      "' (uncertainty dropped)"
    )
  } else {
    NA_character_
  }
  season_result(hit$value, warning = warning)
}

# v3: `breeding_migration` (NA stays NA, no assumption)
recode_breeding_migration <- function(raw, col) {
  if (is.na(raw)) {
    return(season_result(NA_character_))
  }

  tokens <- clean_key(split_tokens(raw))
  hits <- breeding_migration_token_lookup[
    match(tokens, breeding_migration_token_lookup$token),
  ]

  if (length(tokens) == 0 || anyNA(hits$value)) {
    return(season_result(raw, error = unrecognized_error(raw, col)))
  }

  value <- paste(intersect(season_levels, hits$value), collapse = season_sep)
  warning <- if (any(hits$uncertain)) {
    paste0(col, ": '", raw, "' recoded to '", value, "' (uncertainty dropped)")
  } else {
    NA_character_
  }
  season_result(value, warning = warning)
}

# v4+: validate only, never modify. Only "," is accepted as a separator, so
# "breeding; migration" is flagged rather than passed.
check_season_value <- function(raw, col) {
  if (is.na(raw)) {
    return(season_result(NA_character_))
  }

  tokens <- split_tokens(raw, pattern = ",")
  if (length(tokens) > 0 && all(tokens %in% season_levels)) {
    return(season_result(raw))
  }
  season_result(
    raw,
    error = paste0(
      col,
      ": '",
      str_trunc(raw, 60),
      "' not in allowed values (",
      paste(season_levels, collapse = ", "),
      ")"
    )
  )
}

# ---- Main function ----------------------------------------------------------
# on_invalid = "error"   (default): values that can't be cleaned are noted in
#                         `errors` (sheet should go to taxa_flagged).
# on_invalid = "warning": the same notes go to `warnings` instead, and `errors`
#                         is left untouched.

standardize_life_history_season <- function(
  df,
  col = "tx1_life_history_season",
  version_col = "original_version",
  nonbreeding_versions = c("v1", "v2"),
  breeding_migration_versions = "v3",
  on_invalid = c("error", "warning")
) {
  on_invalid <- match.arg(on_invalid)

  if (!"warnings" %in% names(df)) {
    df$warnings <- NA_character_
  }
  if (!"errors" %in% names(df)) {
    df$errors <- NA_character_
  }

  # Recode each unique (version, value) pair once, then join back
  key <- df |>
    distinct(.version = .data[[version_col]], .raw = .data[[col]]) |>
    mutate(
      result = map2(.raw, .version, \(raw, version) {
        if (version %in% nonbreeding_versions) {
          recode_nonbreeding_legacy(raw, col)
        } else if (version %in% breeding_migration_versions) {
          recode_breeding_migration(raw, col)
        } else {
          check_season_value(raw, col)
        }
      })
    ) |>
    unnest(result)

  # Downgrade errors to warnings if requested
  if (on_invalid == "warning") {
    key <- key |>
      mutate(
        .warning = append_note(.warning, .error),
        .error = NA_character_
      )
  }

  df |>
    left_join(key, by = setNames(c(".version", ".raw"), c(version_col, col))) |>
    mutate(
      "{col}" := .value,
      warnings = append_note(warnings, .warning),
      errors = append_note(errors, .error)
    ) |>
    select(-.value, -.warning, -.error)
}

# ---- Example usage ----------------------------------------------------------
# df_clean <- standardize_life_history_season(harmonized_df)
# df_clean <- standardize_life_history_season(harmonized_df, on_invalid = "warning")
#
# # Anything still needing a human look:
# df_clean |> filter(str_detect(errors, "tx1_life_history_season")) |>
#   count(original_version, tx1_life_history_season)
#
# # Should only contain allowed values (or ", " combos) and NA:
# df_clean |> count(tx1_life_history_season)
