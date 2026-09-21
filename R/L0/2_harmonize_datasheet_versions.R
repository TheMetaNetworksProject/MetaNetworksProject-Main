# TITLE:            Harmonize data sheet schema versions
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:    Phoebe Zarnetske, Lucas Mansfield, Jenna Baljunas, Minyoung Lee, Patrick Bills
# DATA INPUT:       CSV files listed in aux_files_with_schema.csv (path: ./R/L0/aux_files_with_schema.csv),
#                    each tagged with a schema_name (schema_1 through schema_10) identifying which of
#                    the historical column layouts that file was collected under
# DATA OUTPUT:      A single, harmonized data frame combining every schema (schema_1 through
#                    schema_10) into the latest unified column structure, with an original_version
#                    column recording which meaningful version each row's source file came in as
# DATE:             initiated: August 2026; updated: 11 September 2026 (fixed schema_1/2/4/5/6
#                    source-URL normalize bug, registered schema_3; fixed concatenate_cols()
#                    logical/character type mismatch; fixed add_missing_cols() zero-row crash;
#                    forced character typing at read time; fixed source_url_backfilled's and
#                    source_URL/text_excerpt's logical/character mismatches (later found incomplete,
#                    see below); added diagnose_column_types(); now skips blank files via
#                    aux_schema_common.R's new has_content column; added v5/schema_11; closed a gap in
#                    the source_URL/text_excerpt fix for files with zero source content in any
#                    position; confirmed schema_registry's version mapping and corrected the v1->v2
#                    "no structural change" comment against aux_schema_cols.xlsx; DATA-INTEGRITY FIX:
#                    finalize_harmonized_schema() was silently dropping BOW_evidence, n_studies,
#                    name_changes, and DatabaseSearchURL (all real, intentionally-kept data per the
#                    original crosswalk), and breeding_migration -> tx1_life_history_season was never
#                    a real rename, fragmenting breeding-season data under "nonbreedingseason" for
#                    5 of 6 v1/v2 schemas -- see NOTES)
# OVERVIEW:         Harmonizes each raw data sheet to the newest schema version, one file at a time.
#                    A small registry maps each schema_name to (a) the meaningful "version" of the
#                    data-collection protocol it represents, and (b) any column-naming quirks specific
#                    to that schema that need fixing before it matches its version's canonical shape.
#                    A second registry holds one "upgrader" per version transition (v1->v2, v2->v3,
#                    v3->v4), capturing only the changes that reflect real changes to the data
#                    (as opposed to incidental naming differences between data sheets of the same
#                    version). harmonize_datasheet() runs a single file through its schema fix and then
#                    the chain of version upgraders up to the newest version, tagging the file with
#                    original_version along the way so that tag is never touched again.
# REQUIRES:         [FILL IN]
# NOTES:            Many "schemas" are just incidental column-naming/ordering differences between data
#                    sheets that don't represent a real change to what was collected -- those get
#                    folded together under one version via schema_registry. Only three transitions
#                    represent real protocol changes: v2->v3 (collapsing per-source URL/notes columns
#                    into long source_URL/text_excerpt rows) and v3->v4 (renaming to the taxa1/taxa2
#                    convention and adding several new tracked fields). v1->v2 has no structural
#                    change in the current data and is kept as an explicit identity step so the
#                    upgrade chain stays uniform.
#
#                    To add a schema in the future: add one entry to schema_registry with its version
#                    and any needed column fixes. To add a new version: append it to version_sequence
#                    and add one function to version_upgraders for the new transition. Nothing else in
#                    this file needs to change.
#
#                    UPDATE (11 Sept 2026): the original refactor was written without the real CSVs
#                    in hand and wrongly assumed schema_1, schema_2, schema_4, and schema_5 already
#                    used the canonical sourceA_URL/B/C/D naming -- they actually use the same
#                    sourceAupdatedURL/OLDsourceA-B layout as schema_6, which threw a "missing
#                    expected column(s)" error out of reshape_sources(). schema_3 was also missing
#                    from schema_registry entirely. Both were fixed against Kelly's 1_schema_cols.csv
#                    column-presence audit (see schema_registry comments below for specifics). This
#                    fix was AI-assisted from that audit and has not yet been re-verified against the
#                    raw CSVs -- see VERIFICATION at the bottom of this file.
#
#                    UPDATE (11 Sept 2026, same day): concatenate_cols() also failed on real data --
#                    a file with an entirely-blank sourceAupdatedURL-derived column had it typed
#                    logical by read.csv(), which couldn't combine with the character column it was
#                    being folded into. Fixed by coercing old_cols to character before combining (see
#                    concatenate_cols() above). The same logical/all-NA-column pattern could in
#                    principle resurface wherever add_missing_cols()-created columns meet real data of
#                    the same name at the final bind_rows() -- not yet seen in practice, flagging as a
#                    place to check if a similar "can't combine" error shows up there.
#
#                    UPDATE (11 Sept 2026, same day): add_missing_cols() also crashed on a zero-row
#                    file (index 1055 in file_info) -- `df[[col]] <- NA` errors with "replacement has
#                    1 row, data has 0" against an empty data frame. Fixed by assigning
#                    rep(NA, nrow(df)) instead of a bare NA. Not yet confirmed whether file 1055 is a
#                    genuinely empty (header-only) raw CSV or something else -- worth a quick
#                    nrow(read.csv(...)) check on it.
#
#                    UPDATE (11 Sept 2026, same day): the character/logical mismatch resurfaced a
#                    third time, now at the final bind_rows() ("Can't combine `taxa1_common`
#                    <character> and <logical>") -- one file's species1_common was entirely blank, so
#                    read.csv() typed it logical there but character elsewhere. Rather than keep
#                    patching each new spot this shows up, fixed it at the source: read.csv() now
#                    uses colClasses = "character", so every column is character in every file,
#                    always. add_missing_cols() updated to add NA_character_ to match. Net effect:
#                    the final harmonized_df/df has every column as character, including ones that
#                    look numeric (e.g. year) -- convert those explicitly downstream if you need them
#                    as numeric. The concatenate_cols() and add_missing_cols() fixes from earlier
#                    today are now largely redundant given this, but left in place as harmless
#                    belt-and-suspenders.
#
#                    UPDATE (11 Sept 2026, same day): one more instance, at bind_rows() again --
#                    "Can't combine `source_url_backfilled` <logical> and <character>". Unlike every
#                    other add_missing_cols() field, source_url_backfilled isn't a raw CSV column: for
#                    files that pass through the v2 upgrader, reshape_sources() sets it directly as
#                    genuine logical TRUE/FALSE, so making add_missing_cols() default to
#                    NA_character_ (the fix above) broke it for native v3/v4 files instead of fixing
#                    it. Handled separately now in the v3 upgrader: a native v3/v4 file gets a literal
#                    FALSE (logical) rather than going through add_missing_cols() for this one field --
#                    the backfill step never ran for it, so FALSE is the correct value, not just a
#                    type-matched placeholder. Checked every other add_missing_cols() call in the
#                    script against aux_schema_cols.csv: all of them add fields that exist natively in
#                    some real schema's raw CSV (so they're genuinely character, matching
#                    NA_character_) or get dropped before bind_rows() in finalize_harmonized_schema
#                    (BOW_evidence, n_studies) -- source_url_backfilled was the only derived,
#                    never-read-from-a-file column in the set.
#
#                    UPDATE (11 Sept 2026, same day): the same ifelse()-defaults-to-test's-type
#                    pattern hit source_URL and text_excerpt in reshape_sources() -- for a file where
#                    a given source position never has real content in any row, the "real value"
#                    branch of ifelse() never fires and the bare NA in the other branch leaves the
#                    whole column logical for that file. Fixed the same way: NA_character_ instead of
#                    NA in both ifelse() calls, so the column is character regardless of whether that
#                    file happens to have any real content in it.
#
#                    Added diagnose_column_types() (see below, after harmonize_all_datasheets()) so
#                    future column-type mismatches like these can be found in one pass across every
#                    file, instead of one bind_rows() crash at a time. Not yet run against the full
#                    aux_files_with_schema.csv -- worth running once before trusting a clean
#                    harmonize_all_datasheets() run.
#
#                    UPDATE (11 Sept 2026, same day): many of the blank-column type mismatches above
#                    trace back to sheets that are themselves blank (header-only, or every cell
#                    NA/empty) rather than genuine data. aux_schema_common.R now computes a
#                    has_content column per file (see file_has_content() there), which flows through
#                    to aux_files_with_schema.csv automatically via the existing audit/register
#                    scripts -- no changes needed to aux_schema_audit.R itself. This script now filters
#                    file_info on has_content right after loading it, before harmonizing anything.
#                    Files where has_content is NA (couldn't be read at all, e.g. the Numbers-file
#                    case) are deliberately kept rather than skipped, so a corrupted file still fails
#                    loudly instead of silently disappearing. Requires re-running
#                    aux_schema_audit.R (or aux_schema_register.R) once so
#                    aux_files_with_schema.csv actually has the has_content column before this filter
#                    can run.
#
#                    UPDATE (11 Sept 2026, same day): added v5 (schema_11), per an updated
#                    aux_schema_cols.csv. Mostly mechanical (new fields: elevation, latitude,
#                    longitude, interaction_confidence, notes, taxa1_resolution, taxa2_resolution --
#                    added via a new version_upgraders[["v4"]] entry), but two things needed Kelly's
#                    confirmation, not just a code fix -- both now confirmed:
#                      (1) taxa1_group/taxa2_group are real columns in schema_11, where every prior
#                          schema had this hardcoded to "bird" in finalize_harmonized_schema(). Fixed
#                          so v5's real values survive (add_missing_cols() now takes a fill= param,
#                          used here instead of the old unconditional mutate()). CONFIRMED: v5 tracks
#                          non-bird taxa -- v1-v4 were bird-bird only. This is a real scope change:
#                          downstream taxonomic matching against AviList/GBIF/the BBS species list
#                          (see taxonomic-harmonization-learnings.md) is bird-specific, so whatever
#                          consumes this script's output next will need a non-bird path for v5 rows,
#                          or a way to route bird vs. non-bird rows differently.
#                      (2) interaction_strength and uncertain_interaction are present in every schema
#                          through v4 and absent in schema_11 -- left as pass-through (older files
#                          keep them, v5 rows are NA). CONFIRMED: intentional removal from the v5
#                          data-collection sheet.
#                    Also: effect_on_tx1/effect_on_tx2 turned out to be schema_11's native names for
#                    what the pipeline calls effect_tx1_on_tx2/effect_tx2_on_tx1 internally -- this was
#                    previously a rename() tacked onto the RUN section, outside the version-upgrade
#                    framework entirely. Folded it into the new v4->v5 upgrader and removed the RUN-
#                    section rename, since leaving it in place would have collided with schema_11's
#                    own effect_on_tx1/effect_on_tx2 columns.
#
#                    UPDATE (11 Sept 2026, same day): the source_URL/text_excerpt fix from earlier
#                    today turned out incomplete -- it only forces character typing when at least one
#                    row triggers an ifelse() assignment. A file with zero rows containing ANY source
#                    URL/notes content in ANY of the 4 positions (real data elsewhere, just never a
#                    citation) has every internal reshape_sources() piece at zero length, so no
#                    assignment ever fires and the column stays logical -- surfaced this file's
#                    logical source_URL colliding with another file's character source_URL at the
#                    final bind_rows(). Closed by coercing source_URL/text_excerpt to character
#                    unconditionally on the combined result, rather than relying on ifelse()'s
#                    branch-triggered coercion.
#
#                    UPDATE (11 Sept 2026, same day): Kelly's aux_schema_cols.xlsx (distinct from the
#                    earlier .csv of the same base name) has a row 2 with explicit version_N/to_N
#                    labels per schema -- e.g. schema_1="version_1", schema_8="version_2",
#                    schema_7="version_4". Checked every schema_registry entry against this: all
#                    match exactly, including schema_7=v4 (settling the raw-version-column-says-3
#                    question from earlier today -- the registry was already right). Also used it to
#                    directly compare v1 vs v2's canonical schemas (schema_1 vs schema_8), which
#                    surfaced a real difference -- see the v1->v2 comment above for what changed and
#                    why it doesn't affect the final output. Worth asking Kelly whether this row 2
#                    labeling should get captured somewhere persistent (aux_schema_metadata.csv?)
#                    rather than living only in a one-off xlsx.
#
#                    UPDATE (11 Sept 2026, same day) -- DATA-INTEGRITY FIX, not just a mechanics bug:
#                    Kelly provided Avian_Interaction_Data_Admin_Notes.pdf, the original manual
#                    schema-to-version conversion instructions this whole registry/upgrader design is
#                    based on. Checked finalize_harmonized_schema()'s drop list and the v3 upgrader
#                    against it and found real data loss on every run of this script to date:
#                      - BOW_evidence, n_studies: the PDF's own notes say these were deliberately KEPT
#                        during the original manual conversion (backfilled with "not_evaluated"), not
#                        deleted as originally instructed. Was being dropped unconditionally.
#                      - name_changes: native column in schema_7/v4 per aux_schema_cols.csv -- never
#                        should have been in the drop list at all.
#                      - DatabaseSearchURL: PDF Step 3 explicitly adds this (empty) to v1 sheets so it
#                        survives into the combined dataset. Was being dropped unconditionally; now
#                        added via the v1 upgrader instead.
#                      - breeding_migration -> tx1_life_history_season: PDF Step 8 says this is a
#                        rename (real values preserved), but the v3 upgrader only ever added
#                        tx1_life_history_season as an empty column via add_missing_cols(), and
#                        separately, the nonbreedingseason -> breeding_migration rename was only ever
#                        done in schema_8's own normalize -- schema_1/2/4/5 never got it at all. Their
#                        breeding-season data has been sitting under "nonbreedingseason" this entire
#                        time, never reaching breeding_migration or tx1_life_history_season. This is
#                        the field behind the frequency table in the PDF ("yes", "not_evaluated",
#                        "breeding", etc.) -- real recorded values for tens of thousands of rows.
#                    Fixed: renamed normalize_updated_source_urls() to normalize_shared_v1v2_naming()
#                    and added the breeding_migration rename to it (schema_1/4/5 now get it directly;
#                    schema_2 additionally gets name_changes added, per PDF Step 1); the v3 upgrader
#                    now does tx1_life_history_season = breeding_migration as a real rename; the v1
#                    upgrader now adds DatabaseSearchURL; finalize_harmonized_schema()'s drop list is
#                    gone entirely. Every prior run of this script, including throughout today's
#                    debugging, has been missing this data -- worth treating any earlier output as
#                    unreliable for these fields specifically and re-running from scratch.
#
#                    Not fully resolved: what happens to DatabaseSearchURL at v4->v5 is undocumented
#                    (schema_11 lacks it, per aux_schema_cols.csv, but whether that's a deliberate
#                    drop or a rename into a new v5 field like "notes" is unknown) -- currently just
#                    left to be naturally NA for v5 rows, same treatment as interaction_strength/
#                    uncertain_interaction. Worth asking Kelly.
#
#                    CORRECTION (11 Sept 2026, same day): n_studies and name_changes were NOT part of
#                    the data-integrity bug above -- confirmed with Kelly that dropping both was
#                    deliberate (not useful information), same as they'd been before today. Only
#                    BOW_evidence, DatabaseSearchURL, and breeding_migration were the actual bug.
#                    finalize_harmonized_schema() drops n_studies/name_changes again, scoped narrower
#                    than the old five-column list. Still open: whether BOW_evidence is also a
#                    deliberate drop (it was grouped with n_studies in the PDF's "kept" note, but
#                    Kelly only confirmed n_studies/name_changes) -- currently still being kept per the
#                    original fix, pending confirmation.
#
#                    UPDATE (11 Sept 2026, same day): BOW_evidence confirmed kept (not dropped). Kelly
#                    also changed her mind about the PDF's documented "not_evaluated" placeholder --
#                    those rows should be blank now. finalize_harmonized_schema() converts literal
#                    "not_evaluated" to NA in BOW_evidence (case-sensitive exact match per how the PDF
#                    documents it; no evidence yet of casing variants the way breeding_migration had).
#                    Also confirmed: the nonbreedingseason -> breeding_migration -> tx1_life_history_
#                    season consolidation already implemented today is exactly the intended scope for
#                    this script -- the messy underlying values (the PDF's "yes"/"breeding"/etc.
#                    frequency table) are a separate future cleanup task, not something this script
#                    needs to handle.
#
#                   *NOTE: Original version of this code was manually created, but was refactored and
#                    comments were added using AI. All code was human-reviewed after refactoring.

# Harmonize data sheet versions

library(tidyverse)

file_info_path <- "./R/L0/1_files_with_schema.csv"
file_info <- read.csv(file_info_path)

# Skip files with no real content -- a header-only sheet, or one where every
# cell is NA/blank -- before they ever reach harmonize_datasheet(). Added
# 11 Sept 2026: several of the type mismatches fixed earlier today
# (source_url_backfilled, source_URL/text_excerpt, taxa1_common) traced back
# to files like this producing vacuous all-NA columns that came out a
# different type than the same column in a file with real data.
#
# has_content comes from file_has_content() in aux_schema_common.R, via
# aux_schema_audit.R / aux_schema_register.R -- re-run one of those first if
# aux_files_with_schema.csv doesn't have this column yet.
#
# Keeps has_content == NA (a file that couldn't be read at all, e.g. the
# Numbers-file-as-.csv case from earlier) rather than dropping it silently --
# an unreadable file should still fail loudly in harmonize_datasheet(), not
# disappear here.
n_before <- nrow(file_info)
file_info <- file_info |> filter(is.na(has_content) | has_content)
n_skipped <- n_before - nrow(file_info)
if (n_skipped > 0) {
  message(sprintf(
    "Skipping %d blank/empty file(s) before harmonizing.",
    n_skipped
  ))
}

# ============================================================================
# GENERIC HELPER FUNCTIONS
# (unchanged in spirit from the previous version of this script; all take
# every input they use as an explicit parameter)
# ============================================================================

# Collapse several old columns into one new column per row, keeping only
# unique, non-blank values and joining them with "; "; drops the old columns
# (except when old_cols and new_col overlap)
#
# Coerces old_cols to character first: read.csv() types an entirely-blank
# column as logical (all NA), and c_across() can't combine that with a
# genuine character column from the same row -- "Can't combine <character>
# and <logical>". Any file where one of old_cols happens to be fully blank
# hits this, so the coercion is unconditional rather than schema-specific.
concatenate_cols <- function(df, old_cols, new_col) {
  df |>
    mutate(across(all_of(old_cols), as.character)) |>
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

# Add each named column as NA if it isn't already present in df; leaves any
# column that already exists untouched. Used by version upgraders to add
# fields that only started being tracked as of that version, without
# clobbering the real values already present in a schema that already
# collected them (or that was already carried through a prior upgrade step).
#
# Uses rep(NA_character_, nrow(df)) rather than a bare NA: every column is
# now read in as character (see harmonize_datasheet's read.csv call), so a
# newly-added column needs to match that type or it hits the same
# character/logical combine error at the final bind_rows(). rep(...) rather
# than a scalar also avoids base R's [[<-.data.frame refusing to assign a
# length-1 value into a zero-row data frame ("replacement has 1 row, data
# has 0"), which a native v3/v4 file with no data rows (or a file
# reshape_sources() filtered down to nothing) would otherwise hit.
#
# fill defaults to NA_character_ but can be overridden (e.g. "bird" for
# taxa1_group/taxa2_group in finalize_harmonized_schema below) -- either way,
# a column that already exists is left untouched, so this never overwrites
# real data with a default.
add_missing_cols <- function(df, cols, fill = NA_character_) {
  for (col in cols) {
    if (!col %in% names(df)) {
      df[[col]] <- rep(fill, nrow(df))
    }
  }
  df
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
# only typed once, in sourceA. Backfilled rows are tagged
# source_url_backfilled = TRUE (rather than silently substituting the value)
# so the downstream audit script can flag and report on them instead of
# letting the substitution pass unnoticed.
reshape_sources <- function(df, url_cols, notes_cols, id_cols = NULL) {
  stopifnot(length(url_cols) == length(notes_cols))

  missing_cols <- setdiff(c(url_cols, notes_cols), names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "reshape_sources(): df is missing expected column(s): %s",
      paste(missing_cols, collapse = ", ")
    ))
  }

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

    out$source_URL <- ifelse(has_content(u_keep), u_keep, NA_character_)
    out$text_excerpt <- ifelse(has_content(n_keep), n_keep, NA_character_)
    out$source_url_backfilled <- backfilled
    out$.orig_row <- df$.orig_row[keep]
    out
  })

  result <- do.call(rbind, pieces)
  result <- result[order(result$.orig_row), ]
  result$.orig_row <- NULL
  rownames(result) <- NULL

  # Unconditional, not just the ifelse(..., NA_character_) above: if a file
  # has zero rows with any content in ANY of the 4 source positions (real
  # data elsewhere -- species, interaction, recorder -- just never a
  # citation), every piece above is zero-length, no ifelse() branch ever
  # assigns anything, and the column stays whatever type `test` started as
  # (logical) -- the NA_character_ fix only helps when at least one row
  # triggers an assignment. Confirmed hitting this 11 Sept 2026 on a file
  # with no source content in any position. Explicit coercion here closes
  # the gap regardless of row count.
  result$source_URL <- as.character(result$source_URL)
  result$text_excerpt <- as.character(result$text_excerpt)

  result
}

# ============================================================================
# SCHEMA REGISTRY
# Maps every schema_name to the (meaningful) version it represents, plus a
# `normalize` function that fixes whatever incidental column-naming quirks
# are specific to that one schema -- bringing it in line with the shared
# canonical shape for its version. Most schemas need no fixing at all.
#
# schema_1, schema_2, schema_4, schema_5, and schema_6 all share the same
# quirk: their raw source-URL columns are named sourceAupdatedURL /
# sourceBupdatedURL / sourceCupdatedURL / sourceDupdatedURL, with older
# entries carried in OLDsourceA / OLDsourceB, instead of the canonical
# sourceA_URL / sourceB_URL / sourceC_URL / sourceD_URL. Confirmed against
# aux_schema_cols.csv (11 Sept 2026) -- normalize_shared_v1v2_naming()
# below is the shared fix; schema_6 layers its own GoogleScholarURL rename
# on top of it.
#
# TO ADD A FUTURE SCHEMA: add one entry here. If it's a minor naming variant
# of an existing version, set normalize to whatever renames/reshapes bring it
# in line with that version's other schemas. If it represents a genuinely new
# version, see version_sequence / version_upgraders below instead.
# ============================================================================

# Shared fix for schema_1, schema_2, schema_4, schema_5, schema_6: rename
# the sourceX_updatedURL columns to the canonical sourceX_URL names, fold
# the old OLDsourceA/OLDsourceB entries into sourceA_URL, and rename
# nonbreedingseason to breeding_migration.
#
# Renamed from normalize_updated_source_urls() (11 Sept 2026) after finding a
# real bug: the breeding_migration rename was previously only done in
# schema_8's own normalize (as its "one differently-named column"), on the
# wrong assumption that schema_1/2/4/5 didn't need it. Per
# Avian_Interaction_Data_Admin_Notes.pdf (the original schema-to-version
# conversion instructions), ALL v1/v2 schemas with nonbreedingseason needed
# this same rename -- schema_1/2/4/5's breeding-season data was silently
# sitting under "nonbreedingseason" the entire time, never reaching
# breeding_migration or (at v4) tx1_life_history_season at all. See the v3
# upgrader below for the second half of this fix.
normalize_shared_v1v2_naming <- function(df) {
  df |>
    rename(
      sourceA_URL = sourceAupdatedURL,
      sourceB_URL = sourceBupdatedURL,
      sourceC_URL = sourceCupdatedURL,
      sourceD_URL = sourceDupdatedURL,
      breeding_migration = nonbreedingseason
    ) |>
    concatenate_cols(c("OLDsourceA", "OLDsourceB"), "Oldsource") |>
    concatenate_cols(c("Oldsource", "sourceA_URL"), "sourceA_URL")
}

schema_registry <- list(
  schema_1 = list(version = "v1", normalize = normalize_shared_v1v2_naming),

  # schema_2: same shared fix as schema_1/4/5, plus its own quirk -- per
  # Avian_Interaction_Data_Admin_Notes.pdf Step 1, schema_2 sheets need
  # name_changes added (they're the only v1/v2 schema natively missing it,
  # confirmed against aux_schema_cols.csv). Not fixing an active bug the way
  # the breeding_migration rename is -- bind_rows() already fills a
  # genuinely-missing column with correctly-typed NA -- but matches the
  # documented process exactly, so added for clarity or in case something
  # later depends on the column already existing.
  schema_2 = list(
    version = "v1",
    normalize = function(df) {
      df |>
        normalize_shared_v1v2_naming() |>
        add_missing_cols("name_changes")
    }
  ),

  schema_5 = list(version = "v1", normalize = normalize_shared_v1v2_naming),

  schema_4 = list(version = "v2", normalize = normalize_shared_v1v2_naming),

  # schema_6: same source-URL fix as above, plus its own quirk -- a
  # GoogleScholarURL column where every other v1/v2 schema either already
  # uses, or entirely lacks, DatabaseSearchURL.
  schema_6 = list(
    version = "v2",
    normalize = function(df) {
      df |>
        rename(DatabaseSearchURL = GoogleScholarURL) |>
        normalize_shared_v1v2_naming()
    }
  ),

  # schema_8: already uses the canonical sourceA_URL/B/C/D and notesA-D
  # naming natively -- only its one differently-named column needs fixing.
  schema_8 = list(
    version = "v2",
    normalize = function(df) rename(df, breeding_migration = nonbreedingseason)
  ),

  # schema_3: already at the v3 shape natively (source_URL, text_excerpt,
  # source_citation, interaction_strength, time_of_year, breeding_migration,
  # species1_lifestage/species2_lifestage all present per aux_schema_cols.csv)
  # -- no renaming needed. Added 11 Sept 2026; was previously missing from
  # this registry entirely, which would have errored the moment a schema_3
  # file was processed. Not yet spot-checked against its raw file -- see
  # VERIFICATION at the bottom of this file.
  schema_3 = list(version = "v3", normalize = function(df) df),

  # schema_9: has its own Citation column where later schemas use
  # source_citation.
  schema_9 = list(
    version = "v3",
    normalize = function(df) rename(df, source_citation = Citation)
  ),

  # schema_10: never captured a citation at all. Confirmed against
  # aux_schema_cols.csv (11 Sept 2026) -- no Citation or source_citation
  # column present natively.
  schema_10 = list(
    version = "v3",
    normalize = function(df) mutate(df, source_citation = NA)
  ),

  schema_7 = list(version = "v4", normalize = function(df) df),

  # schema_11: first v5 schema, and so far the only one -- its raw shape
  # defines what "canonical v5" means, the same way schema_7 did for v4.
  # Added 11 Sept 2026 per aux_schema_cols.csv. No naming quirks found
  # against that column audit, so identity normalize -- revisit if a second
  # v5 schema shows up with different naming.
  schema_11 = list(version = "v5", normalize = function(df) df)
)

# ============================================================================
# VERSION UPGRADE CHAIN
# One function per transition, keyed by the version being upgraded FROM.
# Each captures only the changes that reflect a real change in what was
# collected -- never per-schema naming fixes (those belong in
# schema_registry above).
#
# TO ADD A FUTURE VERSION: append its name to version_sequence, and add a
# version_upgraders[["<previous latest version>"]] entry describing how to
# upgrade into it. Nothing else needs to change.
# ============================================================================

version_sequence <- c("v1", "v2", "v3", "v4", "v5")

version_upgraders <- list(
  # v1 -> v2: the one real difference is DatabaseSearchURL, a field that
  # starts at v2 and is absent from every v1 schema natively. Per
  # Avian_Interaction_Data_Admin_Notes.pdf Step 3, v1 sheets get this column
  # added (empty) explicitly so the combined dataset has it consistently --
  # NOT because it's meant to be discarded, as finalize_harmonized_schema()
  # previously (wrongly) did. See that function below for the fuller fix;
  # this add_missing_cols() call is the v1-specific half of it.
  v1 = function(df) add_missing_cols(df, "DatabaseSearchURL"),

  # v2 -> v3: the real change is collapsing the per-source sourceX_URL /
  # notesX wide columns into long source_URL / text_excerpt rows, and the
  # data started tracking life stage, interaction strength, time of year,
  # and source citation.
  v2 = function(df) {
    df |>
      reshape_sources(
        url_cols = c(
          "sourceA_URL",
          "sourceB_URL",
          "sourceC_URL",
          "sourceD_URL"
        ),
        notes_cols = c("notesA", "notesB", "notesC", "notesD")
      ) |>
      add_missing_cols(c(
        "species1_lifestage",
        "species2_lifestage",
        "interaction_strength",
        "time_of_year",
        "source_citation"
      ))
  },

  # v3 -> v4: rename to the taxa1/taxa2 convention (replacing the
  # species1/species2 naming used since v1), drop other_species1 (no longer
  # part of the unified schema), and add the fields that started being
  # tracked at v4.
  #
  # tx1_life_history_season = breeding_migration fixed 11 Sept 2026: this was
  # previously in the add_missing_cols() list below, which created an empty
  # column instead of migrating real data -- combined with the missing
  # nonbreedingseason->breeding_migration rename for schema_1/2/4/5 (see
  # normalize_shared_v1v2_naming() in schema_registry above), this was
  # silently destroying every pre-v4 file's breeding-season data. Per
  # Avian_Interaction_Data_Admin_Notes.pdf Step 8 ("Convert 'breeding_
  # migration' into 'tx1_life_history_season'"), it's meant to be a straight
  # rename. Every v1/v2/v3-native file has breeding_migration present by this
  # point (v1/v2 via the schema-level rename fixed above; v3 natively, per
  # aux_schema_cols.csv), so this doesn't need an existence check the way
  # source_url_backfilled below does -- if some file is somehow still missing
  # it, rename() erroring is the right outcome, not silently creating an
  # empty column again.
  #
  # source_url_backfilled is handled separately from the add_missing_cols()
  # fields below because it isn't a raw-data field at all -- reshape_sources()
  # (in the v2 upgrader) sets it as genuine logical TRUE/FALSE for every file
  # that passes through it. A native v3/v4 file skips that step entirely, so
  # add_missing_cols()'s NA_character_ doesn't apply here: the right value is
  # a literal FALSE (the backfill logic never ran for this file, which isn't
  # the same as "unknown"), and it has to stay logical to match
  # reshape_sources()'s output at the final bind_rows(). The fields in the
  # add_missing_cols() call below are genuine raw-CSV fields (present natively
  # in schema_7/v4 per aux_schema_cols.csv), so NA_character_ is correct for
  # them -- they match the character type those columns are read in as
  # everywhere else.
  v3 = function(df) {
    if (!"source_url_backfilled" %in% names(df)) {
      df$source_url_backfilled <- rep(FALSE, nrow(df))
    }
    df |>
      rename(
        effect_tx1_on_tx2 = effect_sp1_on_sp2,
        effect_tx2_on_tx1 = effect_sp2_on_sp1,
        taxa1_common = species1_common,
        taxa2_common = species2_common,
        taxa1_scientific = species1_scientific,
        taxa2_scientific = species2_scientific,
        taxa1_lifestage = species1_lifestage,
        taxa2_lifestage = species2_lifestage,
        interaction_excerpt = text_excerpt,
        tx1_life_history_season = breeding_migration
      ) |>
      add_missing_cols(c(
        "n_studies",
        "BOW_evidence",
        "tx2_life_history_season",
        "country",
        "location",
        "timing_location_excerpt",
        "year"
      )) |>
      select(-any_of("other_species1"))
  },

  # v4 -> v5: added 11 Sept 2026 per aux_schema_cols.csv (schema_11).
  #
  # effect_on_tx1/effect_on_tx2 aren't new fields -- they're schema_11's
  # native names for what's been called effect_tx1_on_tx2/effect_tx2_on_tx1
  # internally since the v3->v4 step. This used to be a rename() tacked onto
  # the very end of the script, outside the version-upgrade framework (see
  # the RUN section's history); since v5 already uses this naming natively,
  # folding it into this upgrader means every file converges on the same
  # names by the time it reaches v5, the same as any other transition here.
  #
  # New fields as of v5: elevation, latitude, longitude (structured
  # geolocation alongside the existing free-text `location`),
  # interaction_confidence, notes, taxa1_resolution, taxa2_resolution.
  #
  # taxa1_group/taxa2_group are NOT added here even though schema_11 has real
  # data in them -- see finalize_harmonized_schema() below, which needs to
  # treat them differently (defaulting pre-v5 files to "bird" without
  # clobbering v5's real values).
  #
  # interaction_strength and uncertain_interaction are present in every
  # schema through v4 and absent in schema_11 -- left untouched here (not
  # added, not dropped): pre-v5 files keep whatever they have, v5 files are
  # simply NA for them via bind_rows(). Confirmed intentional (Kelly, 11 Sept
  # 2026): dropped deliberately from the v5 data-collection sheet.
  v4 = function(df) {
    df |>
      rename(
        effect_on_tx2 = effect_tx1_on_tx2,
        effect_on_tx1 = effect_tx2_on_tx1
      ) |>
      add_missing_cols(c(
        "elevation",
        "interaction_confidence",
        "latitude",
        "longitude",
        "notes",
        "taxa1_resolution",
        "taxa2_resolution"
      ))
  }
)

# ============================================================================
# FINAL SCHEMA CLEANUP
# Applied once, unconditionally, after every file has been brought up to the
# newest version -- regardless of whether it arrived there natively or via
# the upgrade chain. Drops a couple of confirmed-not-useful fields, and
# stamps the fields that are constant for this dataset.
#
# Used to also unconditionally drop BOW_evidence and DatabaseSearchURL here,
# alongside n_studies/name_changes, and to drop breeding_migration instead of
# renaming it. Corrected 11 Sept 2026 after checking against
# Avian_Interaction_Data_Admin_Notes.pdf (the original schema-to-version
# conversion instructions): BOW_evidence and DatabaseSearchURL turned out to
# be real, intentionally-retained data per that document (BOW_evidence kept
# per its own notes -- though Kelly has since decided the "not_evaluated"
# placeholder that document describes should be blank instead, see the
# BOW_evidence step below; DatabaseSearchURL deliberately added to v1 sheets
# so it'd survive -- see the v1 upgrader above), and breeding_migration was
# meant to be renamed to tx1_life_history_season, not dropped (see the v3
# upgrader above). This function was silently destroying all three on every
# run until today.
#
# n_studies and name_changes are different: initially assumed to be part of
# the same bug (the PDF's notes group n_studies with BOW_evidence as
# "kept"), but confirmed with Kelly (11 Sept 2026) that dropping both was in
# fact a deliberate decision -- not useful information -- so they're still
# dropped below, just no longer lumped in with the three that were a real
# bug.
# ============================================================================

finalize_harmonized_schema <- function(df) {
  df |>
    # n_studies, name_changes: confirmed with Kelly (11 Sept 2026) as a
    # deliberate decision -- not useful information -- not the data-loss bug
    # BOW_evidence/DatabaseSearchURL/breeding_migration turned out to be (see
    # NOTES above). Scoped narrower than the old drop list: only these two.
    select(-any_of(c("n_studies", "name_changes"))) |>
    # "bird" default for every file through v4, where taxa1_group/taxa2_group
    # never existed as real data. schema_11 (v5) has genuine values here, so
    # add_missing_cols()'s "leave existing columns alone" behavior is load-
    # bearing -- a plain mutate(taxa1_group = "bird") would have silently
    # overwritten v5's real data. Confirmed (Kelly, 11 Sept 2026): v5 does
    # track non-bird taxa -- v1-v4 were bird-bird only. Real scope change,
    # not just a column rename; see downstream note in NOTES above re:
    # taxonomic matching against bird-specific sources (AviList/GBIF/BBS).
    add_missing_cols(c("taxa1_group", "taxa2_group"), fill = "bird") |>
    # BOW_evidence: kept (confirmed with Kelly, 11 Sept 2026), but she
    # changed her mind about the "not_evaluated" placeholder from the
    # original manual conversion (Avian_Interaction_Data_Admin_Notes.pdf) --
    # those rows should just be blank now, not "not_evaluated". add_missing_
    # cols() first because schema_7/v4 and schema_11/v5 native files never
    # get BOW_evidence added by any upgrader (they don't need the v3->v4
    # upgrader at all, and neither natively has this column per
    # aux_schema_cols.csv) -- without this, na_if() below would error on
    # those files for referencing a column that doesn't exist yet.
    # Case-sensitive exact match on "not_evaluated" only, per how the PDF
    # documents it -- if real data turns out to have casing/spelling
    # variants the way breeding_migration did, this will need broadening;
    # no evidence of that for BOW_evidence yet.
    add_missing_cols("BOW_evidence") |>
    mutate(BOW_evidence = na_if(BOW_evidence, "not_evaluated"))
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Harmonize a single raw data sheet to the newest schema version.
#
# file:              path to one raw CSV
# schema_name:       which schema (schema_1, schema_2, ...) this file was
#                     registered under (see aux_schema_register.R)
# schema_registry:   named list, see above
# version_upgraders: named list, see above
# version_sequence:  character vector of versions oldest to newest, see above
#
# Returns the file's data harmonized to the newest version's columns, with
# original_version recording the (meaningful) version this file's schema
# natively belonged to -- set once, immediately after load, and never
# touched by anything downstream.
harmonize_datasheet <- function(
  file,
  schema_name,
  schema_registry,
  version_upgraders,
  version_sequence
) {
  if (!schema_name %in% names(schema_registry)) {
    stop(sprintf(
      paste(
        "Schema '%s' (file: %s) is not registered in schema_registry.",
        "Add an entry for it -- with its native version and any column",
        "fixes it needs -- before harmonizing this file."
      ),
      schema_name,
      file
    ))
  }

  schema_def <- schema_registry[[schema_name]]
  native_version <- schema_def$version

  if (!native_version %in% version_sequence) {
    stop(sprintf(
      "Schema '%s' is registered with version '%s', which is not present in version_sequence (%s).",
      schema_name,
      native_version,
      paste(version_sequence, collapse = ", ")
    ))
  }

  # 1. Load the raw file and tag it with the version it originally came in
  #    as. This column is never modified again by anything below.
  #
  #    colClasses = "character": read.csv() otherwise infers a column's type
  #    per-file, so a column that's entirely blank in one file comes in as
  #    logical while the same column with real data in another file comes in
  #    as character -- which bind_rows() (and any mutate() combining columns
  #    across a row) then refuses to combine. Forcing character at read time
  #    removes the type-inference step that causes this, for every column,
  #    rather than patching each place downstream where two differently-typed
  #    versions of the same column collide.
  out <- read.csv(file, colClasses = "character") |>
    mutate(source_file = basename(file), original_version = native_version)

  # 2. Fix up whatever column-naming quirks are specific to this one schema,
  #    so it matches the shared canonical shape for its native version.
  out <- schema_def$normalize(out)

  # 3. Walk the version chain from this file's native version up to the
  #    newest version, applying each transition's real (meaningful) change.
  from_index <- match(native_version, version_sequence)
  if (from_index < length(version_sequence)) {
    for (v in version_sequence[from_index:(length(version_sequence) - 1)]) {
      out <- version_upgraders[[v]](out)
    }
  }

  # 4. Apply the one-time cleanup that defines the final unified schema.
  out |>
    finalize_harmonized_schema() |>
    clean_na()
}

# Harmonize every file listed in file_info and combine the results.
# Uses dplyr::bind_rows() (rather than base rbind()) so this doesn't depend
# on every file ending up with identical columns in identical order -- any
# column missing for a given file is simply filled with NA in the combined
# result.
harmonize_all_datasheets <- function(
  file_info,
  schema_registry,
  version_upgraders,
  version_sequence
) {
  file_info |>
    purrr::pmap(function(file, schema_name, ...) {
      harmonize_datasheet(
        file,
        schema_name,
        schema_registry,
        version_upgraders,
        version_sequence
      )
    }) |>
    dplyr::bind_rows()
}

# ============================================================================
# DIAGNOSTIC: check column-type consistency across every file, in one pass
# ============================================================================
# Added 11 Sept 2026 after several rounds of bind_rows() failing on one
# column at a time (source_url_backfilled, source_URL, taxa1_common, ...) --
# each one a column that came out logical for some file(s) and character for
# others. Rather than finding these one crash at a time, this runs every file
# through harmonize_datasheet() individually (skipping, not stopping on, any
# file that errors) and reports every column where the type disagrees across
# files, plus which files are on which side. Run this after any schema_registry
# / normalize / upgrader change, before trusting harmonize_all_datasheets() to
# complete.
#
# Usage:
#   type_report <- diagnose_column_types(file_info, schema_registry, version_upgraders, version_sequence)
#   type_report$mismatches   # one row per (column, type) combination that occurs
#   type_report$failures     # files that errored out of harmonize_datasheet() entirely
diagnose_column_types <- function(
  file_info,
  schema_registry,
  version_upgraders,
  version_sequence
) {
  failures <- list()

  per_file_types <- file_info |>
    purrr::pmap(function(file, schema_name, ...) {
      out <- tryCatch(
        harmonize_datasheet(
          file,
          schema_name,
          schema_registry,
          version_upgraders,
          version_sequence
        ),
        error = function(e) {
          failures[[length(failures) + 1]] <<- tibble::tibble(
            file = file,
            schema_name = schema_name,
            error = conditionMessage(e)
          )
          NULL
        }
      )
      if (is.null(out)) {
        return(NULL)
      }
      tibble::tibble(
        file = file,
        column = names(out),
        type = purrr::map_chr(out, ~ class(.x)[1])
      )
    }) |>
    purrr::compact() |>
    dplyr::bind_rows()

  mismatches <- per_file_types |>
    dplyr::group_by(column) |>
    dplyr::filter(dplyr::n_distinct(type) > 1) |>
    dplyr::group_by(column, type) |>
    dplyr::summarise(
      n_files = dplyr::n(),
      example_files = paste(head(file, 3), collapse = "; "),
      .groups = "drop"
    ) |>
    dplyr::arrange(column, type)

  list(
    mismatches = mismatches,
    failures = dplyr::bind_rows(failures)
  )
}

# ============================================================================
# RUN
# ============================================================================

harmonized_df <- harmonize_all_datasheets(
  file_info,
  schema_registry,
  version_upgraders,
  version_sequence
)

df <- harmonized_df |>
  filter(interaction != "co-occur")

# ============================================================================
# VERIFICATION (do this once, before retiring the previous version of this
# script)
# ============================================================================
# Status as of 11 Sept 2026: the aux_schema_cols.csv column-presence audit
# confirmed and fixed the schema_1/2/4/5/6 source-URL naming bug (they were
# using sourceAupdatedURL/OLDsourceA-B, not sourceA_URL, and schema_1/2/4/5
# were wrongly registered with an identity normalize) and confirmed
# schema_10 truly has no Citation-equivalent column. schema_3 was present in
# the column audit but missing from schema_registry entirely -- added as
# v3/identity based on its column pattern; not yet spot-checked against its
# raw file.
#
# Still open: the column-presence audit only confirms which columns exist,
# not that their values are unchanged. Before retiring the previous
# sequential version of this script, compare this version's output against
# it on the real files:
#
# old_df <- read.csv("./temp_concatenated_csv.csv")
# new_df <- df
#
# files_new <- unique(new_df$source_file)
# files_orig <- unique(old_df$source_file)
# sum(!(files_new %in% files_orig))
# sum(!(files_orig %in% files_new))
# all(files_orig %in% files_new)
# new_df_sub <- new_df |>
#   filter(source_file %in% files_orig) |>
#   select(-version, -original_version) |>
#   select(colnames(old_df))
# new_df_sub <- new_df_sub |> arrange(source_file, taxa1_common)
# old_df <- old_df |>
#  arrange(source_file, taxa1_common) |>
#  mutate(
#    effect_on_tx1 = as.character(effect_on_tx1),
#    effect_on_tx2 = as.character(effect_on_tx2)
#  ) |>
#  select(-version, -X)
# old_df <- old_df[, order(names(old_df))] |> arrange(source_file, taxa1_common)
# new_df_sub <- new_df_sub[, order(names(new_df_sub))] |>
#  arrange(source_file, taxa1_common)
#
# waldo::compare(old_df2, new_df_sub2) -> t
#   setdiff(names(old_df), names(new_df))   # columns lost in the refactor
#   setdiff(names(new_df), names(old_df))   # columns added in the refactor
#   nrow(old_df) == nrow(new_df)
#   # then sort both the same way (e.g. by source_file + a row index) and
#   # compare cell-by-cell, e.g. with waldo::compare(old_df, new_df) or
#   # all.equal(old_df, new_df)
#
# Remaining likely spots for a mismatch: whether v1->v2 is truly a content
# no-op (structurally consistent per the column audit, but not checked at
# the value level), and schema_3's registration above.
