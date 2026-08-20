## =============================================================================
## aux_schema_audit.R
## Read-only audit. Uses the FROZEN schema numbering in aux_schema_metadata.csv.
## It never assigns new numbers: if any CSV has a column combination that is not
## already in the key, it stops with an error listing them and tells you to run
## aux_schema_register.R first.
##
## Outputs (only written once every current schema is registered):
##   aux_schema_cols.csv       presence/absence matrix
##   aux_schema_metadata.csv   schema key (numbering frozen, metadata refreshed)
##   aux_files_with_schema.csv per-file details
## =============================================================================

source("./R/auxiliary_scripts/aux_schema_common.R")

schema_map <- read_schema_map()

if (is.null(schema_map)) {
  stop(
    "No schema key found at '",
    schema_key_path,
    "'.\n",
    "Run aux_schema_register.R once to create it before auditing.",
    call. = FALSE
  )
}

## ---- enforce the freeze: every current schema must already be registered ----
current_schemas <- unique(valid$schema)
unknown <- setdiff(current_schemas, names(schema_map))

if (length(unknown)) {
  offending <- valid[valid$schema %in% unknown, c("file", "schema")]
  detail <- vapply(
    unknown,
    function(s) {
      files <- offending$file[offending$schema == s]
      paste0(
        "  - ",
        s,
        "\n",
        "      ",
        length(files),
        " file(s), e.g. ",
        files[1]
      )
    },
    character(1)
  )

  stop(
    length(unknown),
    " unregistered schema(s) found. The schema key is frozen, ",
    "so the audit will not assign numbers.\n",
    "Run aux_schema_register.R to register them, then re-run this audit.\n\n",
    "Unregistered schemas:\n",
    paste(detail, collapse = "\n"),
    call. = FALSE
  )
}

## ---- all schemas known: assign frozen names, refresh metadata, write --------
file_info$schema_name <- schema_map[file_info$schema] # NA schema stays NA
valid$schema_name <- schema_map[valid$schema]

schema_key <- build_schema_key(valid, schema_map) # numbering frozen; metadata refreshed
presence_df <- build_presence(schema_map)

write.csv(presence_df, presence_path, row.names = FALSE)
write.csv(schema_key, schema_key_path, row.names = FALSE)
write.csv(file_info, file_info_path, row.names = FALSE)
