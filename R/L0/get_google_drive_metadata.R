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
