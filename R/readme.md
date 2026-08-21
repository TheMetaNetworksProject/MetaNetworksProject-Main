# MetaNetworks Project Code: 
## Workflow for cleaning and building database

###  [Spatial and Community Ecology Lab (SpaCE Lab)](https://www.communityecologylab.com)

https://github.com/TheMetaNetworksProject/MetaNetworksProject-Main


## Overview

For an overview of the project, details about the database, its structure, and a protocol 
for how the data are pulled from primary sources, see the [Project readme file](../readme.md) 
in the root directory. 

This documents the process and R code for cleaning and building
the MetaNetwork from a collection of data entry tables entered over time
by contributors to the database, primarily workers in the 
[Spatial and Community Ecology Lab (SpaCE Lab)](https://www.communityecologylab.com)

The build process and scripts in this section are for use by project collaborators only
and provided as a reference.  For details about our workflow, see [Project readme file](../readme.md) 


## Location of data

See the [main documentation for the project](../readme.md) for a link to the finished 
database (the output of this process). 

The R folders in this project do have some support data used to harmonize and update the
taxonomic designations for species to match current species lists.  See 
the "*reconcile taxonomy*" step below, in the data folder of this repository. 

## Main database build scripts [OUTDATED AS OF 21 AUG 2026]

* `R/L0/1_generate_species_lists.R` = Generates species lists used for taxonomic harmonization and regional subsetting
* `R/L0/2_stitch_species.qmd` = stitches together all individual csvs in /L0/species
* `R/L1/3_subset_species_lists.R` = generates regional taxonomic crosswalk species checklist for Canada, Alaska, and the Continental United States (CONUS)
* `R/L1/4_clean_network_data.qmd` = fixes species names, interaction codes, checks species name discrepancies based on current and past Clements names.  
* `R/L1/5_subset_network.qmd` = subsets interaction network to only include focal species in the subset species list generated in script 3. 
* `R/L1/6_generate_final_network_checklist.R` = creates final Clements list of all taxa in the AvianMetaNetwork
* `R/L2/7_figure_processing_vignette.qmd` = provides centralized data loading, cleaning and utility functions that are used in the phylogeny, network and interaction distribution figures
* `R/L2/8_summary_vignette.qmd` = counts of records by categories of final database 

## Folders

- `R/L0`: code to examine, clean, and aggregate the version-controlled data entry files
- `R/L1`: code to clean and harmonize taxonomic entries for the final database, 
  and to create subsets for specific analyses
- `R/L2`: code for creating simple summaries and visualizations of the data in the database
- `R/lib`: scripts with shared functions used by main database build scripts
- `R/archive`: code from previous versions saved for reference
- `R/auxiliary scripts`: support scripts not used in the workflow, but helpful for evaluation, etc. 

## Getting Started [OUTDATED AS OF 21 AUG 2026]

Summary of the steps to be able to run these scripts and build the database. This 
assumes the use of Rstudio 2025 version or above.

1. Setup 
   - clone the private git repository with the in-progress (aka 'raw') data  
     from https://github.com/AvianMetaNetwork/AvianMetaNetwork-Working.git
     to a folder on your computer.  Note the location of this folder for steps later. 
     If you are a collaborator and you don't have access, please contact the project
     director. 
   - copy file `R/filepaths_example.R` to `R/filepaths.R` and set files paths 
     pointing to data on your computer (details below). 
   - install packages as needed (details below)
   - clear R environment (scripts do not do this automatically)
1. Optional: check file paths/repository state
   - open `R/auxilliary_script/L0_repo_status.qmd` Quarto file
   - in Rstudio, in the upper-right "run" button, select
     "restart R and run all chunks"
   - if there are no errors, the data is available and you may proceed.
   - if there are errors, check if `dir.exists(DATA_FOLDER)` 
1. Optional/occasional: rebuild species lists
   * `R/L0/1_generate_species_lists.R` = Generates species lists used for taxonomic harmonization and regional subsetting
   Recent species lists are in the [data folder](../data) of this repository and only need to be
   recreated if new lists are available from our primary sources
1. Aggregate (stitch) raw data into single file
   - `R/L0/2_stitch_species.qmd` = stitches together all individual CSVs in /L0/species
   - in the upper-right "run" button, select
     "restart R and run all chunks"
   - this will report the file that is saved
1. Build species checklist for current region of study 
   -  `R/L1/3_subset_species_lists.R` = generates regional taxonomic crosswalk species checklist for Canada, Alaska, and the Continental United States (CONUS)

1. Build taxonomy edits, running one chunk at time
   - open `R/L1/4_clean_network_data.qmd` = harmonizes species names, interaction codes, checks species name discrepencies based on current and past Clements names.  
   - edit the value for stitched_L0_file to match the L0 step above (near the top of file)
   - check the value for the main checklists 
   - position the cursor in the first block of code and run it
   - easily run all subsequent blocks, one a time, using key short cut Option+Command+N
     (see the "->Run" button at the top for more options)
   - edit or add new taxonomic fixes to the edit list

1. Subset for specific analysis
   -  some analyses only include focal species in the subset species list generated in script 3. 
   - `R/L1/5_subset_network.qmd` = subsets interaction network
   
1. Generate final taxa list with Clements names
   - `R/L1/6_generate_final_network_checklist.R`: generate complete list of species in the database (including non-focal taxa) and their Clements/eBird checklist names

1. Summarize and visualize results
   - `7_figure_processing_vignette.qmd`: step-by-step instructions for generating phylogeny and other summary figures
   - `8_summary_vignette.qmd`: summary statistics and overview of AvianMetaNetwork 

![detailed AMN workflow diagram](../docs/images/amn_detailed_workflow_diagram_2025.png)

## Detailed Set-up and Configuration for R code

These are the steps for collaborators to get this R code working to be able to 
build the database and generate summary reports and figures. 

To use these R scripts to build the database, you must set up the 
configuration for where to find the data, as each computer/execution environment 
has its own folder paths.  
To allow for collaboration, this project uses a simple R script that only sets 
variables with the paths.  
Then there is a function you can call (or gets called when you source the scripts)
to check that they are set and the paths are found. 

1. find the file `filepaths_example.R` in the top folder
2. make a copy of this file as filepaths.R  (open and 'save as...' `filepaths.R`)
   the configuration functions expect the file to be named this, and the file
   is included in the gitignore so it is not synced with this repository (each 
   user will need to create their own `filepaths.R`)
3. open the new `filepaths.R` and put the paths for your computer
   (this is an R script and uses R syntax, not a config or environment file)
   - DATA_FOLDER : the path to the folder that has the L0 and L1 subfolders.
   - CHECKLIST_FOLDER : location of various checklist files in the repository.

Example `filepaths.R` contents (see also the content of the file `filepaths_example.R`)

```
# path the clone of the in-progress data repository
DATA_FOLDER =  "/Users/USERID/AvianMetaNetwork-Working"
# Path for for L0 and L1 checklists (Clements etc):
CHECKLIST_L0 = "./data/L0/species_checklists"
CHECKLIST_L1 = "./data/L1/species_checklists"
```

### Installing Packages Details

This project uses the widely used ['here' package](https://here.r-lib.org) to 
automatically identify the top folder for scripts to be able to find each other 
regardless of where they are run. Install this package.

To install all of the packages required for this project we use the [renv](https://rstudio.github.io/renv/articles/renv.html)
package manager from Rstudio/Posit as follows from the R console


```
# if you don't have renv installed, first install it
install.packages("renv")
# this installs all the packages listed in the "renv.lock" file 
renv::init()
```

Choose option 1. restore the project from the lockfile. 

If you need to update packages, choose option 2 to re-install everything. 

See the file `renv.lock` for both the R version and package versions with 
which the code was developed and tested. 



## Additional scripts

These are used by collaborators for building and cleaning the database

- **R/lib/config.R** sourced by all scripts to set file paths, should not need editing or
sourcing.
- **R/lib/shared_functions.R** sources by most scripts, common functions for cleaning and opening the DB
  Using a script for functions helps to keep the quarto notebook files succinct. 
- **R/lib/taxonomy_functions.R** functions used by `R/L1/4_clean_network_data.qmd` for taxonomic harmonization, 
  to keep that quarto notebook readable. 
  - **R/lib/figure_processing.R** functions used by `R/L2/7_figure_processing_vignette.qmd` for generating data paper figures (e.g., phylogeny)
    - **R/lib/interaction_categories_and_colors.R** functions used to standardize colors for interactions across L2 scripts
- **R/auxiliary_scripts** current or draft script fragments used by the database team
- **R/archive** scripts from previous iterations used by the database team and can ignored.  


## Acknowledgements 

Funding is provided by Michigan State University (to P.L. Zarnetske), and by a 
MSU Ecology Evolution, and Behavior SEED Grant (to P.L. Zarnetske). 
Original work on a subset of species was funded by the Yale Climate and Energy 
Institute (to P.L. Zarnetske), Erasmus Mundus Fellowship (to S. Zonneveld).

Please see main readme for additional acknowledgments.
