## =============================================================================
## aux_schema_register.R
## The ONLY script that assigns schema numbers. Run it:
##   - once at the start to create the key, and
##   - whenever the audit reports unregistered schemas.
##
## First run (no key yet): numbers all current schemas by file count (desc),
##   writing schema_1, schema_2, ...
## Later runs: finds column combinations not yet in the key and appends them as
##   schema_(N+1), schema_(N+2), ... WITHOUT touching any existing numbers.
## =============================================================================

source("./R/auxiliary_scripts/aux_schema_common.R")

schema_map <- read_schema_map()

# order a set of schema strings by how many current files use them (desc),
# tie-broken by the schema string itself so the result is deterministic
order_by_count <- function(schemas) {
  if (!length(schemas)) {
    return(schemas)
  }
  counts <- table(valid$schema)[schemas]
  counts[is.na(counts)] <- 0
  schemas[order(-as.integer(counts), schemas)]
}

if (is.null(schema_map)) {
  ## ---- bootstrap: first-time creation --------------------------------------
  new_schemas <- order_by_count(unique(valid$schema))
  schema_map <- setNames(paste0("schema_", seq_along(new_schemas)), new_schemas)
  message("Initialised schema key with ", length(new_schemas), " schema(s).")
  changed <- TRUE
} else {
  ## ---- incremental: append only genuinely new schemas ----------------------
  new_schemas <- order_by_count(setdiff(
    unique(valid$schema),
    names(schema_map)
  ))
  changed <- length(new_schemas) > 0
  if (changed) {
    start_n <- max(schema_number(schema_map)) + 1L
    new_names <- paste0(
      "schema_",
      seq(start_n, length.out = length(new_schemas))
    )
    schema_map <- c(schema_map, setNames(new_names, new_schemas))
    message("Registered ", length(new_names), " new schema(s):")
    for (i in seq_along(new_schemas)) {
      message("  ", new_names[i], "  <-  ", new_schemas[i])
    }
  } else {
    message("No new schemas. Key unchanged; nothing written.")
  }
}

if (changed) {
  schema_key <- build_schema_key(valid, schema_map)
  write.csv(schema_key, schema_key_path, row.names = FALSE)
  message("Wrote ", schema_key_path)
}
