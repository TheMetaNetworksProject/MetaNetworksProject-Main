# ---- 0. taxa_group -> GBIF classification filter -----------------------------
taxa_group_to_gbif_filter <- function(taxa_group) {
  filter_field <- dplyr::case_when(
    taxa_group %in% c("bird", "mammal", "amphibian", "reptile") ~ "class",
    taxa_group %in% c("mollusk", "arthropod") ~ "phylum",
    taxa_group %in% c("plant", "fungus") ~ "kingdom",
    TRUE ~ NA_character_ # fish, worm, protist, or unrecognized -- no filter
  )

  filter_value <- dplyr::case_when(
    taxa_group == "bird" ~ "Aves",
    taxa_group == "mammal" ~ "Mammalia",
    taxa_group == "amphibian" ~ "Amphibia",
    taxa_group == "reptile" ~ "Reptilia",
    taxa_group == "mollusk" ~ "Mollusca",
    taxa_group == "arthropod" ~ "Arthropoda",
    taxa_group == "plant" ~ "Plantae",
    taxa_group == "fungus" ~ "Fungi",
    TRUE ~ NA_character_
  )

  data.frame(
    kingdom = dplyr::if_else(
      filter_field == "kingdom",
      filter_value,
      NA_character_
    ),
    phylum = dplyr::if_else(
      filter_field == "phylum",
      filter_value,
      NA_character_
    ),
    class = dplyr::if_else(
      filter_field == "class",
      filter_value,
      NA_character_
    ),
    stringsAsFactors = FALSE
  )
}
# ---- 1. Classify each unique name before it ever hits GBIF ------------------
taxa_classify_name_string <- function(raw_name) {
  clean_name <- stringr::str_squish(raw_name)
  word_count <- stringr::str_count(clean_name, "\\S+")

  # cf./aff. (tentative ID) and numbered/lettered morphospecies codes --
  # neither will resolve to a real GBIF taxon, so these never get queried
  is_excluded <- stringr::str_detect(
    clean_name,
    "\\bcf\\.?\\b|\\baff\\.?\\b|\\bsp{1,2}\\.\\s*[0-9A-Za-z]+$"
  )

  # single word, or a bare sp./spp./unid./indet. with nothing after it --
  # expected to resolve at genus or higher, never species
  is_higher_rank <- !is_excluded &
    (word_count == 1 |
      stringr::str_detect(
        clean_name,
        "\\bsp{1,2}\\.?$|\\bunid\\.?$|\\bindet\\.?$"
      ))

  name_category <- dplyr::case_when(
    is_excluded ~ "excluded",
    is_higher_rank ~ "higher_rank_expected",
    TRUE ~ "full_name"
  )

  # strip the trailing qualifier so GBIF gets just the bare genus/family/order name
  query_name <- dplyr::if_else(
    name_category == "higher_rank_expected",
    stringr::str_squish(stringr::str_remove(
      clean_name,
      "\\s*\\b(sp{1,2}|unid|indet)\\.?$"
    )),
    clean_name
  )
  query_name <- dplyr::if_else(
    name_category == "excluded",
    NA_character_,
    query_name
  )

  data.frame(
    raw_name = raw_name,
    clean_name = clean_name,
    query_name = query_name,
    name_category = name_category,
    stringsAsFactors = FALSE
  )
}

# ---- 2. Match against GBIF, with optional group filter ----------------------
taxa_match_gbif <- function(
  query_names,
  taxa_group = NULL,
  # bucket_size = 50,
  # sleep = 2,
  verbose = FALSE
) {
  name_data <- data.frame(
    scientificName = query_names,
    stringsAsFactors = FALSE
  )

  if (!is.null(taxa_group)) {
    name_data <- cbind(name_data, taxa_group_to_gbif_filter(taxa_group))
  }

  rgbif::name_backbone_checklist(
    name_data = name_data,
    verbose = verbose #,
    # bucket_size = bucket_size,
    # sleep = sleep
  )
}
# ---- 3. Resolve conflicting taxa_group assignments per unique name ----------
# Same raw name should always carry the same taxa_group -- if it doesn't,
# that's a data-entry problem worth flagging, not silently picking one.
taxa_resolve_group_conflicts <- function(names_vector, taxa_group_vector) {
  data.frame(
    raw_name = names_vector,
    taxa_group = taxa_group_vector,
    stringsAsFactors = FALSE
  ) |>
    dplyr::filter(!is.na(raw_name)) |>
    dplyr::distinct() |>
    dplyr::group_by(raw_name) |>
    dplyr::summarise(
      n_distinct_groups = dplyr::n_distinct(taxa_group),
      group_conflict = n_distinct_groups > 1,
      # if conflicting, don't guess -- fall back to unfiltered matching
      taxa_group = dplyr::if_else(
        group_conflict,
        NA_character_,
        dplyr::first(taxa_group)
      ),
      .groups = "drop"
    )
}
# ---- 4. Orchestrator: dedup -> classify -> match -> join back -> triage -----
taxa_build_gbif_crosswalk <- function(
  names_vector,
  taxa_group_vector
) {
  stopifnot(length(names_vector) == length(taxa_group_vector))

  unique_names <- taxa_resolve_group_conflicts(names_vector, taxa_group_vector)
  classified <- taxa_classify_name_string(unique_names$raw_name) |>
    dplyr::left_join(unique_names, by = "raw_name")

  queryable <- classified[classified$name_category != "excluded", ]
  excluded <- classified[classified$name_category == "excluded", ]

  match_results <- taxa_match_gbif(
    query_names = queryable$query_name,
    taxa_group = queryable$taxa_group
  )

  matched <- cbind(queryable, match_results) |>
    dplyr::mutate(
      is_synonym = stringr::str_detect(status, "SYNONYM"),
      final_usageKey = as.integer(dplyr::if_else(
        is_synonym & !is.na(acceptedUsageKey),
        acceptedUsageKey,
        usageKey
      )),
      match_status = dplyr::case_when(
        group_conflict ~ "needs_review_group_conflict",
        is.na(usageKey) ~ "needs_manual_id",
        matchType %in% c("EXACT", "VARIANT") ~ "matched",
        matchType == "FUZZY" &
          confidence > 90 ~ "matched_fuzzy_high_confidence",
        matchType == "FUZZY" ~ "needs_review_fuzzy",
        matchType == "HIGHERRANK" &
          name_category == "higher_rank_expected" ~ "matched",
        matchType == "HIGHERRANK" ~ "needs_review_rank_mismatch",
        TRUE ~ "needs_review_other"
      )
    )

  excluded <- excluded |>
    dplyr::mutate(
      final_usageKey = NA_integer_,
      match_status = "excluded_manual_review"
    )

  dplyr::bind_rows(matched, excluded)
}

taxa1 <- df |>
  select(taxa1_scientific, taxa1_group) |>
  rename(taxa_scientific = taxa1_scientific, taxa_group = taxa1_group) |>
  unique()
taxa2 <- df |>
  select(taxa2_scientific, taxa2_group) |>
  rename(taxa_scientific = taxa2_scientific, taxa_group = taxa2_group) |>
  unique()

harmon <- rbind(taxa1, taxa2) |> unique()

crosswalk <- taxa_build_gbif_crosswalk(
  names_vector = harmon$taxa_scientific,
  taxa_group_vector = harmon$taxa_group
)

crosswalk_new <- crosswalk

taxa_count_avilist_matches <- function(crosswalk, avilist_2025) {
  avilist_combined <-
    avilist_2025 |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character)) |>
    tidyr::unite(
      "all_cols",
      dplyr::everything(),
      sep = " ",
      remove = TRUE,
      na.rm = TRUE
    ) |>
    dplyr::pull(all_cols)

  crosswalk |>
    dplyr::mutate(
      n_avilist_rows = purrr::map_int(
        query_name,
        ~ sum(stringr::str_detect(avilist_combined, stringr::fixed(.x)))
      )
    )
}
crosswalk_new$query_name[
  crosswalk_new$query_name == "Cynanthus auriceps)"
] <- "Cynanthus auriceps"

crosswalk_new <- taxa_count_avilist_matches(crosswalk_new, avilist_2025)
