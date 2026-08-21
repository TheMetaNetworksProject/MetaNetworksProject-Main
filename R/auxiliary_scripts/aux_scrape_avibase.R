# TITLE:            aux_scrape_avibase.R
# PROJECT:          AvianMetaNetwork
# AUTHORS:          Kelly Kapsar
# COLLABORATORS:
# DATA INPUT:       Locally-saved HTML file of an Avibase regional checklist page
#                   (e.g. "avibase8.17_cac.html"), NOT a web URL — see NOTES.
# DATA OUTPUT:      Data frame with columns: common_name, scientific_name, status,
#                   order, family, region. Optionally written to CSV at
#                   L0_dir/avibase8.17_<region_code>.csv
# DATE:             initiated: 11 August 2026
# OVERVIEW:         Parses a saved Avibase checklist HTML page into a tidy species
#                   table for one region, extracting order/family from section
#                   headers and carrying them down through species rows.
# REQUIRES:         rvest, dplyr, stringr, readr
# NOTES:            Avibase (avibase.bsc-eoc.org) has implemented anti-webscraping
#                   protection. To get the information on the checklists, you can
#                    open the checklist URL in a normal browser, save the page as
#                   "Webpage, HTML only" (not "complete"), and pass the local file
#                   path to this function's `url` argument in place of a live URL.
#
#                   This means checklist updates require a manual re-save per
#                   region rather than a scheduled/automated scrape.

#                   Documentation and code created with AI-assistance. All code,
#                   documentation, and outputs were human-reviewed for accuracy.

# Specify functions
read_avibase <- function(region_code, url, L0_dir = NULL, save_output = FALSE) {
  message("Processing region: ", region_code)
  message("WARNING: This scraper assumes data are in avibase version 8.17.")
  library(rvest)
  library(tidyr)
  library(dplyr)
  library(stringr)

  tab <- read_html(url) %>%
    html_table(fill = TRUE) %>%
    .[[1]]

  # Rename expected columns
  tab <- tab %>%
    rename(
      common_name = X1,
      scientific_name = X2,
      status = X3
    ) %>%
    # Extract order/family headings
    mutate(
      order = str_extract(common_name, "\\b[A-Z]+(?: [A-Z]+)*(?=: )"),
      family = str_extract(common_name, "(?<=: )[A-Z][a-z]+")
    ) %>%
    # Carry order/family down through species rows
    fill(order, family) %>%
    filter(!(common_name == paste(order, family, sep = ": "))) %>%
    mutate(region = region_code) %>%
    # Trim whitespace just in case
    mutate(across(c(common_name, scientific_name, status), ~ str_squish(.)))

  # Save raw cleaned table for that region
  out_file <- file.path(L0_dir, paste0("avibase8.17_", region_code, ".csv"))
  if (save_output) {
    write_csv(tab, out_file)
  }

  return(tab)
}
