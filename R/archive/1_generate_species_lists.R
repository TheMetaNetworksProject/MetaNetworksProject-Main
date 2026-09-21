# TITLE:          L0 Species Checklist Data: Pulls in raw lists from sources and
#                   creates formatted versions of lists as L0 data

# AUTHORS:        Phoebe Zarnetske
# COLLABORATORS:  Vincent Miele, Stephane Dray, Emily Parker. Kelly Kapsar
# DATA INPUT:     Imports L0 raw species list data from:
#                 (1) Clements/eBird Checklist v2024 (Cornell Lab of Ornithology)
#                 (2) the USGS North American Breeding Bird Survey (BBS) SpeciesList
#                 from 2024 release (up to 2023 BBS data; SpeciesList.txt is updated yearly).
#                 (3) CA-CONUS List = AviBase Canada list + AviBase Lower 48 US +
#                 AviBase Alaska list (taxonomy from Clements 2024 list)
#                 (4) AviBase Global URLs, by region; version 8.17 Nov 2024 list
# DATA OUTPUT:    (1) L0 Clements/eBird Cheklist v2024
#                 (2) BBS List L0 data: bbs_specieslist_2024_L0.csv - this is a
#                     copy of the raw data, just omitting the top lines without data
#                 (3) CA.CONUS list L0 data:spp_avibase_cac_2024.csv
#                   - this is data pulled from the AviBase species list website
#                   and formatted
#                 (4) AviBase Global list, by region; version 8.17 Nov 2024 list
# PROJECT:        AvianMetaNet & avian-meta-network
# DATE:           17 January 2022 - 19 February 2026
# NOTES:          bbs_specieslist_2024_L1.csv is produced in bbs_specieslist_L1.R.
#                 Check out this site for code w BBS:
#                 https://rdrr.io/github/davharris/mistnet/src/extras/BBS-analysis/data_extraction/data-extraction.R
#                 For other types of lists check out: https://datazone.birdlife.org/search
#                 which has data on migratory status, conservation status, etc.


# Clear all existing data
rm(list=ls())

# Load necessary libraries
library(dplyr)
library(tidyr)
library(rvest) # for web scraping
library(stringr)
library(readr)
library(purrr)

# Get file paths
source("R/lib/config.R")
file_paths <- get_file_paths()


#### (1) Clements/eBird 2024 Checklist: Cornell Lab of Ornithology
clements2024<-read.csv("https://www.birds.cornell.edu/clementschecklist/wp-content/uploads/2024/10/eBird-Clements-v2024-integrated-checklist-October-2024-rev.csv")

# Export this as its original filename for final cleaning in L1 script.
write.csv(clements2024, file.path(file_paths$CHECKLIST_L0,"eBird-Clements-v2024-integrated-checklist-October-2024-rev.csv"), fileEncoding="UTF-8", row.names=F)

#### (2) BBS List ####
# Below section is modified from: https://rdrr.io/github/davharris/mistnet/src/extras/BBS-analysis/data_extraction/species-handling.R

# Read in the SpeciesList file:
# Reading in a copy placed in the L0 directory on October 22, 2024, and renamed BBS2024_SpeciesListL0.txt
# The original file SpeciesList.csv (from 2024 BBS release) is here: https://www.sciencebase.gov/catalog/item/66d9ed16d34eef5af66d534b
guess_encoding(file.path(file_paths$CHECKLIST_L0,"spp_bbs_2024_raw.csv"))
#UTF-8
bbs.splist.2024<-read.csv(file.path(file_paths$CHECKLIST_L0,"spp_bbs_2024_raw.csv"),fileEncoding="UTF-8")

# Make a column for genus_species
bbs.splist.2024$genus_species<- do.call(paste, c(bbs.splist.2024[c("Genus", "Species")], sep = " "))
dim(bbs.splist.2024)
# 763 species

# The species re-assignment checking will occur in the next script.
# Export the cleaned data (note the encoding to maintain special characters)
write.csv(bbs.splist.2024, file.path(file_paths$CHECKLIST_L0,"spp_bbs_2024_clean.csv"), fileEncoding="UTF-8", row.names=F)

# Next script to run: bbs_specieslist_L1.R
# Then, if combining with bbs_obs data: AvianInteractionData_L1.R

#### AviBase Multi-Region Merger (Clements 2024 taxonomy) ####

#### 1. Function to read & clean one AviBase region ####
read_avibase <- function(region_code, url, L0_dir) {
  message("Processing region: ", region_code)

  # Read HTML and extract first table
  tab <- url %>%
    read_html() %>%
    html_table(fill = TRUE) %>%
    .[[1]]

  # Rename expected columns
  tab <- tab %>%
    rename(
      common_name     = X1,
      scientific_name = X2,
      status          = X3
    ) %>%
    # Extract order/family headings
    mutate(
      order  = str_extract(common_name, "\\b[A-Z]+(?: [A-Z]+)*(?=: )"),
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
  write_csv(tab, out_file)

  return(tab)
}

################################################################################

########## TEMPORARILY REMOVING DIRECT DOWNLOAD SINCE AVIBASE WAS UPDATED FOR
########## 2025 CLEMENTS CHECKLIST
# INSTEAD USING ALREADY DOWNLOADED CHECKLISTS WITH 2024 DATA IN REPO


# #### 2. Define Region URLs ####
# # Major Regions
# region_urls <- list(
#   NAM = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=NAM&version=text",
#   CAM = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=CAM&version=text",
#   SAM = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=SAM&version=text",
#   EUR = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=EUR&version=text",
#   AFR = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=AFR&version=text",
#   ASI = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=ASI&version=text",
#   MID = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=MID&version=text",
#   OCE = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=OCE&version=text",
#   AUS = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=AUS&version=text",
#   PAC = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=PAC&version=text",
#   hol = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=hol&version=text",
#   nea = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=nea&version=text",
#   pal = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=pal&version=text",
#   # Oceans:
#   oaq = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=oaq&version=text",
#   oat = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=oat&version=text",
#   # Arctic Ocean; blank
# #  oar = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=oar&version=text",
#   oin = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=oin&version=text",
#   opa = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=opa&version=text",
#   XX = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=XX&version=text",
#   CA   = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=CA&version=text",
#   #US:
#   US48 = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=US48&version=text",
#   USak   = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=USak&version=text",
#   UShi = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=UShi&version=text",
#   #Caribbean:
#   CAR = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=CAR&version=text",
#   nan = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=nan&version=text",
#   TT = "https://avibase.bsc-eoc.org/checklist.jsp?lang=EN&p2=1&list=clements&region=TT&version=text"
# )
#
# #### 3. Run all regions and combine them ####
# all_tables <- imap(region_urls, ~ read_avibase(.y, .x, file_paths$CHECKLIST_L0))

################################################################################

# 2024 avibase data

### Load in 2024 version of avibase data
all_tables <- list.files(file_paths$CHECKLIST_L0, pattern = "8.17_", full.names = T)
all_tables <- lapply(all_tables, read.csv)

# Fix nan values being input as numeric instead of character in Nan region table
all_tables[[11]]$region <- as.character(all_tables[[11]]$region)

# Generate full data table
all_data <- bind_rows(all_tables)

################################################################################

#### 4. Create wide status columns ####
status_wide <- all_data %>%
select(scientific_name, common_name, order, family, region, status) %>%
  pivot_wider(
    id_cols = c(scientific_name, common_name, order, family),
    names_from = region,
    names_prefix = "status_",
    values_from = status
  )

#### 5. Collapse regions into a single column ####
regions_collapsed <- all_data %>%
  group_by(scientific_name, common_name, order, family) %>%
  summarise(regions = paste(sort(unique(region)), collapse = "; "), .groups = "drop")

#### 6. Final merged dataset ####
global.splist <- status_wide %>%
  left_join(regions_collapsed,
            by = c("scientific_name", "common_name", "order", "family"))

#### 7. Outputs ####
cat("Number of species in global.splist:", n_distinct(global.splist$scientific_name), "\n") #11129; these exclude the family-level species that are in the Clements main list

#### 8. Subset to different regions ####
#### Adjust code below for different subsets
#### Canada & CONUSL North America = CA / US48 / USak ####
ca.conus <- global.splist %>%
  filter(str_detect(regions, "\\bCA\\b|\\bUS48\\b|\\bUSak\\b"))
dim(ca.conus) #1104 species
write.csv(ca.conus, file.path(file_paths$CHECKLIST_L0,"spp_avibase_cac_2024.csv"), fileEncoding="UTF-8", row.names=F)

#### Western Hemisphere ####
west.hsphere <- global.splist %>%
  filter(str_detect(regions, "\\bCA\\b|\\bUS48\\b|\\bUSak\\b|\\bUShi\\b|\\bNAM|\\b|\\bCAM|\\b|\\bSAM|\\b|\\bCAR|\\b|\\boaq|\\b|\\boat|\\b|\\bopa|\\b|\\bXX|\\b"))
dim(west.hsphere)
write.csv(west.hsphere, file.path(file_paths$CHECKLIST_L0,"spp_avibase_westh_2024.csv"), fileEncoding="UTF-8", row.names=F)

# Save Global lookup & species list
write.csv(global.splist, file.path(file_paths$CHECKLIST_L0,"spp_avibase_all_2024.csv"), fileEncoding = "UTF-8", row.names = FALSE)

