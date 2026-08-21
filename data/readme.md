# MetaNetworks Data folder

`/data/readme.md`

These data are support files used for cleaning and building the database:

-   **L0/aux_metadata_colnames_v0.csv**: List of column names and descriptions of data entry CSVs, previous version used from 2024-9/2025

-   **L0/aux_metadata_colnames_v1.csv**: List of column names and descriptions of data entry CSVs, current version used from 10/2025-current (2026)

-   **L0/aux_interactions_defs.csv**: List of interaction types and codes with descriptions with the following columns

    -   type_of_interaction: short name of interaction
    -   asymmetric: yes/no, is the interaction directional rather than the same
    -   taxa 1 or 2: possible values for either interaction code
    -   taxa 2 or 1: possible values for either interaction code
    -   definition: long description of the interaction

-   [**MetaNetwork_DATA_ENTRY_INSTRUCTIONS.md**](../docs/MetaNetwork_DATA_ENTRY_INSTRUCTIONS.md): Detailed protocol for data entry, version control and validation.

-   **L0/species_checklists**: This folder holds checklists downloaded and used by L0 scripts to build L1 checklists lists based on the [Clements/eBird checklist of birds of the world](https://www.birds.cornell.edu/clementschecklist/) and [Avibase World Bird database](https://avibase.bsc-eoc.org/)

-   **L1/aux_taxonomy_resolutions.csv**: List of changes to be applied to harmonize the taxonomic names from data entry files to ensure the database is compatible with current taxonomy based on Clements checklist of birds of the world.See the [documentation for the database workflow](../R/readme.md) for how this is applied.

-   **L1/species_checklists**: This folder holds files are the checklists built from code used in final taxonomic harmonizations

    -   **L1/species_checklists/spp_joint_cac.csv**
    -   **L1/species_checklists/spp_joint_cac_colsubset.csv**

## Note

Any folder labeled archive has files no longer used in our workflow but preserved for reference and comparison.
