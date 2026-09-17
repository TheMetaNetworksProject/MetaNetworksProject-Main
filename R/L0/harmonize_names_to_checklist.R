# TITLE:            harmonize_names_to_checklist.R
# PROJECT:          The MetaNetworks Project
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:
# DATA INPUT:       (1) crosswalk data.frame produced by taxa_build_gbif_crosswalk()
#                       in harmonize_names_to_gbif.R -- one row per unique
#                       MetaNetworks raw_name, already matched to GBIF.
#                   (2) a standardized checklist object from a checklist_load_*()
#                       adapter below (default: AviList v2025 via avilistr).
#                   (3) optional manual-correction CSVs (created by this script,
#                       edited by hand, re-read on the next run).
# DATA OUTPUT:      one crosswalk data.frame: MetaNetworks name x GBIF match x
#                   <checklist> match, with a method column per hop and a
#                   resolved taxonomic hierarchy. aux_gbif_manual_matches.csv
#                   and aux_checklist_manual_matches.csv (review templates /
#                   correction registries, written to disk).
# DATE:             initiated: 17 September 2026
# OVERVIEW:         Extends the existing MetaNetworks -> GBIF crosswalk with a
#                   second pass against a more current species checklist
#                   (default AviList v2025). Handles the case where GBIF's
#                   backbone lags a checklist update (e.g. Accipiter gentilis ->
#                   Astur gentilis) AND the reverse case where MetaNetworks still
#                   has the old name but GBIF has already resolved the synonym.
#                   Generic over checklist source via a small adapter contract
#                   (see section 1) so the same matching/manual-correction logic
#                   works for AviList, a future plant checklist, etc.
# REQUIRES:         harmonize_names_to_gbif.R must have already produced
#                   `crosswalk` (via taxa_build_gbif_crosswalk()), including its
#                   `query_name` column. rgbif, dplyr, stringr. avilistr only if
#                   using the default AviList adapter.
# NOTES:            avilistr's exact column names (Scientific_name, Taxon_rank,
#                   Order, Family) were taken from the package's published docs
#                   and NOT verified by running it -- check checklist_load_avilist()
#                   against avilistr::avilist_metadata before the first real run.
#                   AviList (as shipped by avilistr) appears to carry only
#                   currently-recognized taxa, not a synonym table -- so "direct"
#                   matching below can only succeed when a MetaNetworks name
#                   already equals AviList's current spelling. That's exactly the
#                   case this script needs to catch (Astur gentilis already in
#                   MetaNetworks, GBIF backbone not yet updated), so it's fine,
#                   but it means AviList can never "correct" an old MetaNetworks
#                   name on its own the way GBIF's synonym table can -- that
#                   still has to go through GBIF first (the via-GBIF fallback).
#                   Subspecies and genus/family/order-level MetaNetworks names
#                   are both matchable: checklist_load_avilist() pulls species
#                   AND subspecies rows by default, and synthesizes genus/
#                   family/order entries from their hierarchy columns (see
#                   checklist_add_higher_ranks()) since AviList's own rows
#                   don't obviously include those ranks as standalone entries.
#                   A subspecies name that GBIF's backbone can only resolve to
#                   its parent species (common -- backbone subspecies coverage
#                   is patchy) needs a small companion change in
#                   harmonize_names_to_gbif.R to be treated as "matched"
#                   rather than flagged for manual review -- see the
#                   "subspecies_expected" patch notes kept alongside that
#                   script. Without that patch nothing here breaks, it's just
#                   noisier: those rows land in needs_review_rank_mismatch and
#                   get reviewed one at a time instead of auto-accepted.
#                   This script was drafted without a working R install in the
#                   authoring environment (no interpreter available to test
#                   against) -- run it once on a small subset before trusting it
#                   on the full name list, and treat any error as a starting
#                   point for a fix rather than evidence the whole approach is
#                   wrong.

library(rgbif)
library(avilistr)

# =============================================================================
# DESIGN NOTES (read before editing)
# =============================================================================
#
# MATCH ORDER, per MetaNetworks name:
#   1. direct_exact   -- MetaNetworks raw_name matched against the checklist's
#                         own current names, unchanged. Wins when the checklist
#                         is more current than GBIF (the Astur gentilis case).
#   2. via_gbif_exact  -- if (1) fails, the GBIF-*resolved* name (the accepted
#                         name GBIF's synonym table points to, when the raw name
#                         is a GBIF synonym) is matched against the checklist
#                         instead. Wins when GBIF is more current than
#                         MetaNetworks but the checklist has since caught up too.
#   3. unmatched       -- neither found anything; goes to manual review.
#   Fuzzy matching is deliberately NOT reattempted at the checklist stage:
#   GBIF's own fuzzy/synonym resolution already ran upstream in
#   taxa_build_gbif_crosswalk(), so by the time a name reaches this script it's
#   already as "cleaned up" as automation can make it. Re-fuzzing against a
#   second, smaller checklist mostly just risks a wrong coincidental match. If
#   you want it later, checklist_match_exact() is the place to add an
#   agrep()-based fallback -- keep it gated behind a confidence check the same
#   way the GBIF script gates FUZZY matches at confidence > 90.
#
# HIERARCHY SOURCE: use the checklist's hierarchy whenever the checklist was
#   matched at all (direct OR via-GBIF -- both are exact matches, so both are
#   equally trustworthy for this purpose), and fall back to GBIF's hierarchy
#   only when nothing in the checklist matched. Reasoning: the whole point of
#   harmonizing to a second checklist is that it's assumed more current than
#   GBIF's backbone, so once you're confident you've found the checklist's
#   entry for a name, its classification should supersede GBIF's for anything
#   still pending a backbone update (e.g. genus reassignments). A light
#   `hierarchy_conflict` flag records family-level disagreement between the two
#   sources for audit, but never blocks anything -- consistent with the
#   project's audit-driven-correction pattern (flag from real output, fix by
#   hand, don't try to anticipate every case).
#
# MANUAL CORRECTIONS: two frozen-registry CSVs, one per hop (GBIF, checklist),
#   built FROM pipeline output rather than anticipated -- same pattern as
#   aux_scientific_name_corrections.csv / aux_schema_metadata.csv elsewhere in
#   this project.
#     taxa_export_*_review_template()  appends newly-flagged names to the CSV
#                                       (never overwrites an existing row, so
#                                       hand-entered matches are never clobbered)
#     taxa_apply_*_manual_matches()    reads the CSV back in, overrides match
#                                       results for rows it covers, and
#                                       backfills their hierarchy automatically
#                                       (you supply an ID, not a classification)
#   Workflow: run the pipeline -> export review templates -> fill in the CSVs
#   by hand (a manual id of "NO_MATCH" marks "reviewed, confirmed there isn't
#   one" so it stops being re-flagged) -> re-run the pipeline. Both CSVs join
#   on `raw_name`, the one identifier that's stable across the whole pipeline
#   (unlike the intermediate query name, which can be either the raw name or a
#   GBIF-resolved name depending on which hop mattered). The checklist CSV also
#   carries a `checklist_source` column so one file can serve several
#   checklists over time without their corrections colliding.
#
# =============================================================================

# ---- 1. Checklist adapter contract -----------------------------------------
# Every checklist source needs a checklist_load_<source>() function returning
# a list with:
#   $accepted  data.frame, one row per currently-recognized taxon, columns:
#              checklist_id, checklist_name, checklist_rank,
#              kingdom, phylum, class, order, family, genus, species
#              (hierarchy columns NA where the checklist doesn't provide that
#              rank -- e.g. AviList has no kingdom/phylum/class)
#   $synonyms  data.frame or NULL. If the checklist ships its own synonymy,
#              columns: synonym_name, checklist_id (of the accepted row it
#              points to). NULL means "this checklist has no synonym table",
#              which is the AviList case below.
# Writing a new adapter (e.g. a plant checklist) means writing one function
# that returns this shape -- nothing else in the script needs to change.

checklist_load_avilist <- function(
  rank_filter = c("species", "subspecies"),
  include_higher_ranks = TRUE,
  higher_ranks = c("genus", "family", "order")
) {
  avilist <- avilistr::avilist_2025

  accepted <- data.frame(
    # avilistr does not appear to publish a stable numeric taxon key in this
    # package version -- the scientific name IS the identifier here. Swap this
    # out if/when avilistr adds a persistent key.
    checklist_id = avilist$Scientific_name,
    checklist_name = avilist$Scientific_name,
    checklist_rank = tolower(avilist$Taxon_rank),
    kingdom = NA_character_,
    phylum = NA_character_,
    class = NA_character_,
    order = avilist$Order,
    family = avilist$Family,
    genus = stringr::word(avilist$Scientific_name, 1),
    # word(x, 1, 2) is the GENUS + SPECIES portion regardless of whether this
    # row is itself species- or subspecies-rank -- a subspecies row's own
    # (possibly trinomial) name lives in checklist_name/checklist_id, not here.
    species = stringr::word(avilist$Scientific_name, 1, 2),
    stringsAsFactors = FALSE
  )
  # blank out anything finer than each row's own rank (e.g. a genus-rank row
  # should not carry a leftover `species` value) before rank_filter runs, in
  # case avilist_2025 itself ships genus/family/order rows -- unconfirmed, see
  # NOTES at the top of this file.
  accepted <- checklist_blank_finer_ranks(accepted)

  if (!is.null(rank_filter)) {
    accepted <- accepted[accepted$checklist_rank %in% rank_filter, ]
  }

  if (include_higher_ranks && length(higher_ranks) > 0) {
    accepted <- checklist_add_higher_ranks(accepted, ranks = higher_ranks)
  }

  if (any(duplicated(accepted$checklist_name))) {
    warning(
      "checklist_load_avilist(): duplicate checklist_name values -- ",
      "checklist_match_exact() will use the first match only."
    )
  }

  list(accepted = accepted, synonyms = NULL)
}

# ---- 1a. Rank-aware helpers shared by any checklist_load_*() adapter -------
# Neither of these is AviList-specific -- they operate purely on the
# standardized $accepted shape from section 1, so any adapter can call them.

# Sets any hierarchy column finer than a row's own checklist_rank to NA (e.g.
# a family-rank row keeps kingdom..family but has genus/species blanked).
# Ranks this doesn't recognize (checklist_rank NA, or some other value the
# source uses -- "hybrid", "form", etc.) are left untouched rather than
# guessed at.
checklist_blank_finer_ranks <- function(df) {
  rank_level <- c(
    kingdom = 1,
    phylum = 2,
    class = 3,
    order = 4,
    family = 5,
    genus = 6,
    species = 7,
    subspecies = 7
  )
  hierarchy_cols <- c(
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species"
  )

  row_level <- rank_level[df$checklist_rank]
  row_level[is.na(row_level)] <- length(hierarchy_cols)

  for (col in hierarchy_cols) {
    col_level <- rank_level[[col]]
    blank <- row_level < col_level
    df[[col]][blank] <- NA_character_
  }
  df
}

# Synthesizes one checklist row per distinct genus/family/order value found
# in `accepted`'s hierarchy columns, so a bare "Accipiter" or "Accipitridae"
# in MetaNetworks can get an exact match even when the source checklist only
# ships species/subspecies rows (as AviList's published docs suggest, though
# this wasn't independently confirmed -- if avilist_2025 turns out to already
# have its own genus/family/order rows, they're excluded upstream by
# rank_filter and these synthesized ones are used instead, so behavior is the
# same either way).
checklist_add_higher_ranks <- function(
  accepted,
  ranks = c("genus", "family", "order")
) {
  synthesized <- lapply(ranks, function(r) {
    values <- unique(accepted[[r]])
    values <- values[!is.na(values) & values != ""]
    if (length(values) == 0) {
      return(NULL)
    }

    rows <- accepted[match(values, accepted[[r]]), ]
    rows$checklist_id <- values
    rows$checklist_name <- values
    rows$checklist_rank <- r
    rows
  })

  combined <- dplyr::bind_rows(accepted, synthesized)
  checklist_blank_finer_ranks(combined)
}

# ---- 2. Exact match a vector of names against a standardized checklist -----
# Case-insensitive, whitespace-trimmed exact match only (see design notes for
# why fuzzy isn't attempted here). Checks $accepted first, then $synonyms if
# present. Returns one row per input name (NA columns where nothing matched).
checklist_match_exact <- function(query_names, checklist) {
  key_query <- tolower(stringr::str_squish(query_names))
  accepted_key <- tolower(stringr::str_squish(
    checklist$accepted$checklist_name
  ))
  idx <- match(key_query, accepted_key)

  result <- data.frame(
    query_name = query_names,
    checklist_id = checklist$accepted$checklist_id[idx],
    checklist_name = checklist$accepted$checklist_name[idx],
    checklist_match_source = dplyr::if_else(
      !is.na(idx),
      "accepted",
      NA_character_
    ),
    kingdom = checklist$accepted$kingdom[idx],
    phylum = checklist$accepted$phylum[idx],
    class = checklist$accepted$class[idx],
    order = checklist$accepted$order[idx],
    family = checklist$accepted$family[idx],
    genus = checklist$accepted$genus[idx],
    species = checklist$accepted$species[idx],
    stringsAsFactors = FALSE
  )

  if (!is.null(checklist$synonyms)) {
    needs_synonym_lookup <- is.na(idx)
    if (any(needs_synonym_lookup)) {
      syn_key <- tolower(stringr::str_squish(checklist$synonyms$synonym_name))
      syn_idx <- match(key_query[needs_synonym_lookup], syn_key)
      accepted_via_syn <- match(
        checklist$synonyms$checklist_id[syn_idx],
        checklist$accepted$checklist_id
      )

      rows <- which(needs_synonym_lookup)
      result$checklist_id[rows] <- checklist$accepted$checklist_id[
        accepted_via_syn
      ]
      result$checklist_name[rows] <- checklist$accepted$checklist_name[
        accepted_via_syn
      ]
      result$checklist_match_source[rows] <- dplyr::if_else(
        !is.na(accepted_via_syn),
        "synonym",
        NA_character_
      )
      result$kingdom[rows] <- checklist$accepted$kingdom[accepted_via_syn]
      result$phylum[rows] <- checklist$accepted$phylum[accepted_via_syn]
      result$class[rows] <- checklist$accepted$class[accepted_via_syn]
      result$order[rows] <- checklist$accepted$order[accepted_via_syn]
      result$family[rows] <- checklist$accepted$family[accepted_via_syn]
      result$genus[rows] <- checklist$accepted$genus[accepted_via_syn]
      result$species[rows] <- checklist$accepted$species[accepted_via_syn]
    }
  }

  result
}

# ---- 3. Fetch GBIF usage records directly --------------------------------
# Used by taxa_apply_gbif_manual_matches() to turn a manually-entered
# usageKey into a canonical name + full hierarchy -- a manual match only ever
# comes with an ID, and (unlike an automated match) there's no
# name_backbone_checklist() response row to read a hierarchy from, so this is
# the one place in the script that still needs a live GBIF call per name.
# Always returns the same columns (NA-filled where GBIF doesn't have a value)
# so callers never have to guard for a missing column.
taxa_lookup_gbif_usage <- function(usage_keys) {
  hierarchy_cols <- c(
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species"
  )
  usage_keys <- unique(usage_keys[!is.na(usage_keys)])

  empty <- data.frame(
    usageKey = integer(0),
    canonicalName = character(0),
    stringsAsFactors = FALSE
  )
  for (col in hierarchy_cols) {
    empty[[col]] <- character(0)
  }
  if (length(usage_keys) == 0) {
    return(empty)
  }

  records <- lapply(usage_keys, function(key) {
    usage <- tryCatch(rgbif::name_usage(key = key)$data, error = function(e) {
      NULL
    })
    row <- data.frame(
      usageKey = key,
      canonicalName = NA_character_,
      stringsAsFactors = FALSE
    )
    for (col in hierarchy_cols) {
      row[[col]] <- NA_character_
    }

    if (!is.null(usage) && nrow(usage) > 0) {
      if ("canonicalName" %in% names(usage)) {
        row$canonicalName <- usage$canonicalName[1]
      }
      for (col in hierarchy_cols) {
        if (col %in% names(usage)) row[[col]] <- usage[[col]][1]
      }
    }
    row
  })

  dplyr::bind_rows(records)
}

# ---- 4. Orchestrator: GBIF crosswalk -> <checklist> crosswalk --------------
taxa_build_checklist_crosswalk <- function(
  gbif_crosswalk, # output of taxa_build_gbif_crosswalk()
  checklist, # a checklist_load_*() result
  checklist_source # short label, e.g. "avilist_2025" -- stamped into output
  # and used to key the manual-corrections CSV
) {
  stopifnot(all(
    c("raw_name", "query_name", "final_usageKey", "match_status") %in%
      names(gbif_crosswalk)
  ))

  # ---- 4a. the GBIF-resolved name to match the checklist against -----------
  # Confirmed against GBIF's live match API (2026-09-17) at two rank levels:
  #   - species-rank synonym "Dendroica coronata" -> `species` comes back
  #     "Setophaga coronata" (the ACCEPTED name; speciesKey == acceptedUsageKey)
  #   - genus-rank synonym "Dendroica" -> there's no `species` value at all
  #     (nothing exists at species rank to report), but `genus` comes back
  #     "Setophaga" (again the accepted name)
  #   In both cases canonicalName/scientificName keep the QUERIED synonym's
  #   own spelling ("Dendroica coronata" / "Dendroica"), never the accepted one.
  # So the accepted name always lives in whichever hierarchy column matches
  # the matched taxon's OWN rank -- species for a species-rank match, genus
  # for a genus-rank match, and so on -- not always in `species`. An earlier
  # version of this line only checked `species`, which is right for the
  # ordinary Accipiter/Astur species-level case but silently fell back to the
  # stale synonym name (via canonicalName) for a genus/family/order-level
  # synonym -- exactly the case genus-level matching exists to catch.
  # coalesce() picks the finest non-NA hierarchy column, which is always the
  # matched taxon's own rank whether or not it's a synonym: no live lookup
  # needed, and it's the same "finest non-NA wins" rule
  # checklist_blank_finer_ranks() already applies on the checklist side.
  col_or_na <- function(col) {
    if (col %in% names(gbif_crosswalk)) {
      gbif_crosswalk[[col]]
    } else {
      rep(NA_character_, nrow(gbif_crosswalk))
    }
  }

  gbif_resolved_name <- dplyr::coalesce(
    col_or_na("species"),
    col_or_na("genus"),
    col_or_na("family"),
    col_or_na("order"),
    col_or_na("class"),
    col_or_na("phylum"),
    col_or_na("kingdom"),
    gbif_crosswalk$canonicalName
  )
  # canonicalName is the last resort, for a row where GBIF returned no
  # classification at all (e.g. needs_manual_id) -- that keeps
  # gbif_resolved_name non-NA where possible, but a row like that will still
  # be "unmatched" against the checklist and land in the review CSV, which is
  # the right outcome for a name GBIF itself couldn't place.

  # ---- 4b. which rows are even eligible for checklist matching -------------
  # Genus/family/order-level names ARE matchable now that the checklist
  # carries synthesized higher-rank entries (see checklist_add_higher_ranks())
  # -- only cf./aff./morphospecies codes are structurally never going to match
  # anything, so only "excluded" is kept out of "unmatched" review.
  eligible <- !(gbif_crosswalk$name_category %in% "excluded")

  # ---- 4c. tier 1: direct match on the cleaned MetaNetworks name -----------
  # Uses query_name, not raw_name: query_name is the same cleaned-up string
  # taxa_build_gbif_crosswalk() itself sent to GBIF (whitespace-squished, and
  # for higher_rank_expected rows, with a trailing "sp."/"unid." stripped) --
  # matching on raw_name here would silently fail a bare-genus entry like
  # "Accipiter sp." against the checklist's "Accipiter" row.
  direct <- checklist_match_exact(gbif_crosswalk$query_name, checklist)
  names(direct) <- paste0("direct_", names(direct))

  # ---- 4d. tier 2: match on the GBIF-resolved name, only where tier 1 missed
  via_gbif <- checklist_match_exact(gbif_resolved_name, checklist)
  names(via_gbif) <- paste0("via_gbif_", names(via_gbif))

  crosswalk <- cbind(gbif_crosswalk, direct, via_gbif)
  crosswalk$gbif_resolved_name <- gbif_resolved_name

  crosswalk <- crosswalk |>
    dplyr::mutate(
      checklist_source = checklist_source,
      metanetworks_to_checklist_method = dplyr::case_when(
        !eligible ~ "not_attempted",
        !is.na(direct_checklist_id) ~ paste0(
          "direct_",
          direct_checklist_match_source
        ),
        !is.na(via_gbif_checklist_id) ~ paste0(
          "via_gbif_",
          via_gbif_checklist_match_source
        ),
        TRUE ~ "unmatched"
      ),
      checklist_id = dplyr::coalesce(
        direct_checklist_id,
        via_gbif_checklist_id
      ),
      checklist_name = dplyr::coalesce(
        direct_checklist_name,
        via_gbif_checklist_name
      ),
      hierarchy_source = dplyr::if_else(
        !is.na(checklist_id),
        "checklist",
        "gbif"
      ),
      kingdom = dplyr::coalesce(direct_kingdom, via_gbif_kingdom, kingdom),
      phylum = dplyr::coalesce(direct_phylum, via_gbif_phylum, phylum),
      class = dplyr::coalesce(direct_class, via_gbif_class, class),
      order = dplyr::coalesce(direct_order, via_gbif_order, order),
      # staged separately (not overwritten yet) so hierarchy_conflict below can
      # compare against the still-original GBIF family in this same mutate()
      family_checklist = dplyr::coalesce(direct_family, via_gbif_family),
      genus_final = dplyr::coalesce(direct_genus, via_gbif_genus, genus),
      species_final = dplyr::coalesce(
        direct_species,
        via_gbif_species,
        species
      ),
      # family is the rank most likely to move under an AOS-type reassignment
      # (the Accipiter/Astur case is a genus move, but family-level splits
      # happen too) -- flag disagreement for a human to glance at, never block.
      hierarchy_conflict = !is.na(family_checklist) &
        !is.na(family) &
        tolower(family_checklist) != tolower(family)
    ) |>
    dplyr::mutate(
      family = dplyr::coalesce(family_checklist, family),
      genus = genus_final,
      species = species_final
    ) |>
    dplyr::select(-family_checklist, -genus_final, -species_final)

  crosswalk
}

# ---- 5. Manual corrections: GBIF hop ---------------------------------------
# "needs review" = anything taxa_build_gbif_crosswalk() didn't already accept
# outright (matched / matched_fuzzy_high_confidence) and isn't already covered
# by a prior manual entry in the CSV.
taxa_export_gbif_review_template <- function(gbif_crosswalk, path) {
  flagged <- gbif_crosswalk |>
    dplyr::filter(
      !match_status %in% c("matched", "matched_fuzzy_high_confidence", "manual")
    ) |>
    dplyr::distinct(raw_name, clean_name, name_category, match_status)

  existing <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  } else {
    data.frame(
      raw_name = character(0),
      clean_name = character(0),
      name_category = character(0),
      match_status = character(0),
      manual_gbif_usageKey = character(0),
      manual_gbif_canonicalName = character(0),
      notes = character(0),
      date_added = character(0),
      stringsAsFactors = FALSE
    )
  }

  new_rows <- dplyr::anti_join(flagged, existing, by = "raw_name")
  if (nrow(new_rows) == 0) {
    message("taxa_export_gbif_review_template(): no new names to flag.")
    return(invisible(existing))
  }

  new_rows$manual_gbif_usageKey <- NA_character_
  new_rows$manual_gbif_canonicalName <- NA_character_
  new_rows$notes <- NA_character_
  new_rows$date_added <- as.character(Sys.Date())

  updated <- dplyr::bind_rows(existing, new_rows)
  utils::write.csv(updated, path, row.names = FALSE, na = "")
  message(
    "taxa_export_gbif_review_template(): added ",
    nrow(new_rows),
    " name(s) to ",
    path,
    " -- fill in manual_gbif_usageKey (or \"NO_MATCH\") by hand."
  )
  invisible(updated)
}

# manual_gbif_usageKey == "NO_MATCH" is a sentinel: "a human looked, there
# isn't one" -- distinct from NA/blank ("not reviewed yet"), so confirmed
# non-matches stop being re-flagged by taxa_export_gbif_review_template().
taxa_apply_gbif_manual_matches <- function(gbif_crosswalk, path) {
  if (!file.exists(path)) {
    message(
      "taxa_apply_gbif_manual_matches(): ",
      path,
      " does not exist yet -- nothing applied."
    )
    return(gbif_crosswalk)
  }

  corrections <- utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    colClasses = "character"
  ) |>
    dplyr::filter(!is.na(manual_gbif_usageKey) & manual_gbif_usageKey != "")
  if (nrow(corrections) == 0) {
    return(gbif_crosswalk)
  }

  is_real_match <- corrections$manual_gbif_usageKey != "NO_MATCH"
  hierarchy <- taxa_lookup_gbif_usage(as.integer(corrections$manual_gbif_usageKey[
    is_real_match
  ]))
  hierarchy$usageKey <- as.character(hierarchy$usageKey)

  corrections <- corrections |>
    dplyr::left_join(hierarchy, by = c("manual_gbif_usageKey" = "usageKey"))

  gbif_crosswalk |>
    dplyr::left_join(
      corrections |>
        dplyr::select(
          raw_name,
          manual_gbif_usageKey,
          manual_gbif_canonicalName,
          kingdom,
          phylum,
          class,
          order,
          family,
          genus,
          species
        ),
      by = "raw_name",
      suffix = c("", "_manual")
    ) |>
    dplyr::mutate(
      manual_gbif_usageKey_int = suppressWarnings(as.integer(
        manual_gbif_usageKey
      )),
      is_no_match = manual_gbif_usageKey == "NO_MATCH",
      is_manual_match = !is.na(manual_gbif_usageKey) & !is_no_match,
      final_usageKey = dplyr::if_else(
        is_manual_match,
        manual_gbif_usageKey_int,
        final_usageKey
      ),
      canonicalName = dplyr::if_else(
        is_manual_match,
        manual_gbif_canonicalName,
        canonicalName
      ),
      kingdom = dplyr::if_else(is_manual_match, kingdom_manual, kingdom),
      phylum = dplyr::if_else(is_manual_match, phylum_manual, phylum),
      class = dplyr::if_else(is_manual_match, class_manual, class),
      order = dplyr::if_else(is_manual_match, order_manual, order),
      family = dplyr::if_else(is_manual_match, family_manual, family),
      genus = dplyr::if_else(is_manual_match, genus_manual, genus),
      species = dplyr::if_else(is_manual_match, species_manual, species),
      match_status = dplyr::case_when(
        is_no_match ~ "confirmed_no_match",
        is_manual_match ~ "manual",
        TRUE ~ match_status
      )
    ) |>
    dplyr::select(
      -manual_gbif_usageKey,
      -manual_gbif_canonicalName,
      -manual_gbif_usageKey_int,
      -is_no_match,
      -is_manual_match,
      -kingdom_manual,
      -phylum_manual,
      -class_manual,
      -order_manual,
      -family_manual,
      -genus_manual,
      -species_manual
    )
}

# ---- 6. Manual corrections: checklist hop ----------------------------------
# Same frozen-registry pattern as section 5, keyed additionally by
# checklist_source so one CSV can serve several checklists over time. Uses
# base-R subsetting (not dplyr::filter) for the checklist_source comparisons
# below on purpose: the function argument and the data column share the name
# "checklist_source", and dplyr's data-masking would otherwise silently
# resolve `checklist_source == checklist_source` against the DATA COLUMN on
# both sides (an always-true tautology) once that column exists in the data.
taxa_export_checklist_review_template <- function(
  checklist_crosswalk,
  checklist_source,
  path
) {
  flagged <- checklist_crosswalk |>
    dplyr::filter(metanetworks_to_checklist_method == "unmatched") |>
    dplyr::distinct(raw_name, query_name, gbif_resolved_name, checklist_source)

  existing <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  } else {
    data.frame(
      raw_name = character(0),
      query_name = character(0),
      gbif_resolved_name = character(0),
      checklist_source = character(0),
      manual_checklist_id = character(0),
      manual_checklist_name = character(0),
      notes = character(0),
      date_added = character(0),
      stringsAsFactors = FALSE
    )
  }

  already_covered <- existing[
    !is.na(existing$checklist_source) &
      existing$checklist_source == checklist_source,
  ]
  new_rows <- dplyr::anti_join(flagged, already_covered, by = "raw_name")
  if (nrow(new_rows) == 0) {
    message(
      "taxa_export_checklist_review_template(): no new names to flag for ",
      checklist_source,
      "."
    )
    return(invisible(existing))
  }

  new_rows$manual_checklist_id <- NA_character_
  new_rows$manual_checklist_name <- NA_character_
  new_rows$notes <- NA_character_
  new_rows$date_added <- as.character(Sys.Date())

  updated <- dplyr::bind_rows(existing, new_rows)
  utils::write.csv(updated, path, row.names = FALSE, na = "")
  message(
    "taxa_export_checklist_review_template(): added ",
    nrow(new_rows),
    " name(s) to ",
    path,
    " for ",
    checklist_source,
    " -- fill in manual_checklist_id (or \"NO_MATCH\") by hand."
  )
  invisible(updated)
}

taxa_apply_checklist_manual_matches <- function(
  checklist_crosswalk,
  checklist,
  checklist_source,
  path
) {
  if (!file.exists(path)) {
    message(
      "taxa_apply_checklist_manual_matches(): ",
      path,
      " does not exist yet -- nothing applied."
    )
    return(checklist_crosswalk)
  }

  corrections <- utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    colClasses = "character"
  )
  corrections <- corrections[
    !is.na(corrections$checklist_source) &
      corrections$checklist_source == checklist_source &
      !is.na(corrections$manual_checklist_id) &
      corrections$manual_checklist_id != "",
  ]
  if (nrow(corrections) == 0) {
    return(checklist_crosswalk)
  }

  hier_idx <- match(
    corrections$manual_checklist_id,
    checklist$accepted$checklist_id
  )
  corrections$kingdom <- checklist$accepted$kingdom[hier_idx]
  corrections$phylum <- checklist$accepted$phylum[hier_idx]
  corrections$class <- checklist$accepted$class[hier_idx]
  corrections$order <- checklist$accepted$order[hier_idx]
  corrections$family <- checklist$accepted$family[hier_idx]
  corrections$genus <- checklist$accepted$genus[hier_idx]
  corrections$species <- checklist$accepted$species[hier_idx]

  checklist_crosswalk |>
    dplyr::left_join(
      corrections |>
        dplyr::select(
          raw_name,
          manual_checklist_id,
          manual_checklist_name,
          kingdom,
          phylum,
          class,
          order,
          family,
          genus,
          species
        ),
      by = "raw_name",
      suffix = c("", "_manual")
    ) |>
    dplyr::mutate(
      is_no_match = manual_checklist_id == "NO_MATCH",
      is_manual_match = !is.na(manual_checklist_id) & !is_no_match,
      checklist_id = dplyr::if_else(
        is_manual_match,
        manual_checklist_id,
        checklist_id
      ),
      checklist_name = dplyr::if_else(
        is_manual_match,
        manual_checklist_name,
        checklist_name
      ),
      kingdom = dplyr::if_else(is_manual_match, kingdom_manual, kingdom),
      phylum = dplyr::if_else(is_manual_match, phylum_manual, phylum),
      class = dplyr::if_else(is_manual_match, class_manual, class),
      order = dplyr::if_else(is_manual_match, order_manual, order),
      family = dplyr::if_else(is_manual_match, family_manual, family),
      genus = dplyr::if_else(is_manual_match, genus_manual, genus),
      species = dplyr::if_else(is_manual_match, species_manual, species),
      hierarchy_source = dplyr::if_else(
        is_manual_match,
        "checklist_manual",
        hierarchy_source
      ),
      metanetworks_to_checklist_method = dplyr::case_when(
        is_no_match ~ "confirmed_no_match",
        is_manual_match ~ "manual",
        TRUE ~ metanetworks_to_checklist_method
      )
    ) |>
    dplyr::select(
      -manual_checklist_id,
      -manual_checklist_name,
      -is_no_match,
      -is_manual_match,
      -kingdom_manual,
      -phylum_manual,
      -class_manual,
      -order_manual,
      -family_manual,
      -genus_manual,
      -species_manual
    )
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================
# gbif_crosswalk <- taxa_build_gbif_crosswalk(...)   # from harmonize_names_to_gbif.R
#
avilist <- checklist_load_avilist()

checklist_crosswalk <- taxa_build_checklist_crosswalk(
  gbif_crosswalk = gbif_crosswalk,
  checklist = avilist,
  checklist_source = "avilist_2025"
)

# flag anything that still needs a human:
taxa_export_gbif_review_template(gbif_crosswalk, "aux_gbif_manual_matches.csv")
taxa_export_checklist_review_template(
  checklist_crosswalk,
  "avilist_2025",
  "aux_checklist_manual_matches.csv"
)

# ... fill in the two CSVs by hand, then re-run with corrections applied:
gbif_crosswalk <- taxa_apply_gbif_manual_matches(
  gbif_crosswalk,
  "aux_gbif_manual_matches.csv"
)
checklist_crosswalk <- taxa_build_checklist_crosswalk(
  gbif_crosswalk,
  avilist,
  "avilist_2025"
)
checklist_crosswalk <- taxa_apply_checklist_manual_matches(
  checklist_crosswalk,
  avilist,
  "avilist_2025",
  "aux_checklist_manual_matches.csv"
)

# final columns of interest:
checklist_crosswalk |>
  dplyr::select(
    raw_name,
    final_usageKey,
    canonicalName,
    match_status,
    checklist_source,
    checklist_id,
    checklist_name,
    metanetworks_to_checklist_method,
    hierarchy_source,
    hierarchy_conflict,
    kingdom,
    phylum,
    class,
    order,
    family,
    genus,
    species
  )
