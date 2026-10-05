## =============================================================================
## 1_schema_audit.R
## Audit using the FROZEN schema numbering in 1_schema_metadata.csv.
## It never assigns new numbers. Any CSV whose column combination is not
## already in the key is moved to taxa_flagged and recorded in
## taxa_flagged/flagged_file_metadata.csv (same format clean_data.R appends to),
## and the audit carries on with the remaining files. To recognize that layout,
## run 1b_schema_register.R and update 2_harmonize_datasheet_versions.R.
##
## Outputs (written for all files that fit a registered schema):
##   1_schema_cols.csv       presence/absence matrix
##   1_schema_metadata.csv   schema key (numbering frozen, metadata refreshed)
##   1_files_with_schema.csv per-file details (flagged files are not listed)
##   <taxa_flagged>/flagged_file_metadata.csv  appended/created if files flagged
## =============================================================================

source("./R/L0/_schema_common.R")
source("./R/L0/_flagged_files.R")

## TRUE  = write flagged_file_metadata.csv, move files to taxa_flagged, and
##         write the three output csvs
## FALSE = dry run: list the files that would be flagged, then stop. Nothing
##         is written or moved.
move_flagged <- TRUE

schema_map <- read_schema_map()

if (is.null(schema_map)) {
  stop(
    "No schema key found at '",
    schema_key_path,
    "'.\n",
    "Run 1b_schema_register.R once to create it before auditing.",
    call. = FALSE
  )
}

## ---- flag files whose schema is not registered ------------------------------
current_schemas <- unique(valid$schema)
unknown <- setdiff(current_schemas, names(schema_map))

if (length(unknown)) {
  is_unknown <- valid$schema %in% unknown
  bad_files <- valid$file[is_unknown]
  bad_schemas <- valid$schema[is_unknown]

  flagged_schema <- data.frame(
    source_file = basename(bad_files),
    row = NA_integer_,
    error = paste0(
      "File does not match any registered schema (columns: ",
      bad_schemas,
      "). If this should be a recognized schema, run 1b_schema_register.R ",
      "and modify 2_harmonize_datasheet_versions.R to update the datasheet ",
      "to the newest schema/version, then move the file back to ",
      "taxa_to_check and re-run 1_schema_audit.R."
    ),
    stringsAsFactors = FALSE
  )

  flag_files(
    flagged_schema,
    source_dirs = taxa_source_dirs,
    flagged_dir = flagged_dir,
    move = move_flagged
  )

  if (!move_flagged) {
    # dry run: don't overwrite the output csvs with a partial file list
    stop("Dry run complete (move_flagged = FALSE).", call. = FALSE)
  }

  # moved files no longer exist in the scanned folders, so drop them here
  valid <- valid[!is_unknown, ]
  file_info <- file_info[!(file_info$schema %in% unknown), ]
} else {
  message("0 file(s) added to ", flagged_dir)
}

## ---- assign frozen names, refresh metadata, write ---------------------------
file_info$schema_name <- schema_map[file_info$schema] # NA schema stays NA
valid$schema_name <- schema_map[valid$schema]

schema_key <- build_schema_key(valid, schema_map) # numbering frozen; metadata refreshed
presence_df <- build_presence(schema_map)

write.csv(presence_df, presence_path, row.names = FALSE)
write.csv(schema_key, schema_key_path, row.names = FALSE)
write.csv(file_info, file_info_path, row.names = FALSE)
