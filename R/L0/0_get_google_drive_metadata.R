# TITLE:            0_get_google_drive_metadata.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar, Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas,
#                   Minyoung Lee, Patrick Bills
# DATA INPUT:       Google Sheet of interaction metadata schemas (read-only via googlesheets4),
#                   sheet ID 16CqFzM9VNISBAy9LfZeQPTMWOAuMHOjPc2NSwquErw8; all tabs read as-is
# DATA OUTPUT:      One CSV per sheet tab, named <tab_name>.csv, written to
#                   ./docs/interaction_metadata_schemas/
# DATE:             Summer 2026
# OVERVIEW:         Pulls every tab from the interaction metadata schema Google Sheet and writes
#                   each one to a flat CSV in the repo docs/ directory, so the schema definitions
#                   are version-controlled alongside the processing code rather than living only
#                   in Google Drive.
# REQUIRES:         googlesheets4, readr, purrr, rlang; an authenticated Google account with read
#                   access to the EcologicalNetworks shared drive. Output directory
#                   ./docs/interaction_metadata_schemas/ must already exist.
# NOTES:            Tab names become filenames directly — any tab renamed with spaces, slashes,
#                   or punctuation will produce awkward or invalid filenames; consider a slug step.
#                   rlang::set_names() is called but rlang is not in the library() block (works via
#                   namespace call, but add it for clarity). Overwrites existing CSVs silently, so
#                   diff before committing to catch unintended schema changes.
# NOTE:             This code was created with assistance from an LLM. All outputs were
#                   human-reviewed and tested to verify outputs.

library(googlesheets4)
library(readr)
library(purrr)

gs4_auth(scopes = "https://www.googleapis.com/auth/spreadsheets.readonly")

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
