# The MetaNetworks Project
###  [Spatial and Community Ecology Lab (SpaCE Lab)](https://www.communityecologylab.com)

https://github.com/TheMetaNetworksProject/MetaNetworksProject-Main 

This repository contains code, workflows, documentation, and support data to 
build a biotic interaction network constructed from empirical data synthesis.  

From 2012-2014, Zarnetske and Zonneveld compiled bird-bird interactions among cavity nesting birds 
and their interacting bird species, based on species accounts in the Birds of North America 
(now Birds of the World). This led to an analysis of the influence of biotic interactions on 
North American cavity nesting bird species distributions 
([Belmaker and Zarnetske et al. 2015 GEB](https://onlinelibrary.wiley.com/doi/full/10.1111/geb.12311)). 

Starting in 2019, a new protocol was established and all prior records were updated 
and further bird-bird interactions were added in by Zarnetske and MSU SpaCE Lab undergraduates 
(2019-present). 


## Data Availability

An earlier version of this database, known as the AvianMetaNetwork, along with documentation and code used to generate it is available 
from the Environmental Data Initiative (EDI) repository for download as a zip file: 
*LINK PROVIDED UPON PUBLICATION*

## Overview 

The workflow for this repository follows the guidelines set out by the [Environmental Data Initiative (EDI)]((https://edirepository.org/)). Briefly, this involves aligning with FAIR data practices, and employing a workflow that uses different levels for harmonization and derived data products (see [diagram](https://edirepository.org/static/images/thematic-standardization-workflow.png) for overview).

![main AMN workflowdiagram](docs/images/amn_generalized_workflow_diagram_2025.png)

For Data entry workflow (L0), see our detailed [data entry protocol](/docs/MetaNetwork_DATA_ENTRY_INSTRUCTIONS.md) we make available to all project members.

For data cleaning and harmonizing workflow (L1), as well as summarizing and visualizing the database (L2) see [R script workflow](/R/readme.md)


## Description of subdirectories 

- **[data](/data/readme.md)**
  Directory containing instructions for interaction data entry, metadata, and species checklists (raw in L0, synthesized in L1). Note that species interaction data files are not directly available in this repository, but available for dowload from the EDI repository (see above) upon publication. 
- **[R](/R/readme.md)**
  Code and support files to build a clean and harmonized database from version-controlled data entry files. See [R code documentation](/R/readme.md) for detailed descriptions and instructions for using Code/Workflows and descriptions of the files.

<!-- 
- reports:  notebooks in the R folder that are 'rendered' to HTML are saved here 
- _quarto.yml: configuration file for rendering notebooks

--> 

## Funding 

Funding is provided by Michigan State University (to P.L. Zarnetske), and by a MSU Ecology Evolution, and Behavior SEED Grant (to P.L. Zarnetske). Original work on a subset of species was funded by the Yale Climate and Energy Institute (to P.L. Zarnetske), Erasmus Mundus Fellowship (to S. Zonneveld). 

## Authors of this repository

* Phoebe L. Zarnetske, PI, [Spatial and Community Ecology Lab (SpaCE Lab)](https://www.communityecologylab.com)
* Kelly Kapsar, Post-doctoral Fellow 2025-
* Lucas Mansfield, PhD student 2025-

## Collaborators

* Vincent Miele, CNRS France
* Stephane Dray, University of Lyon and CNRS, France

## Previous Collaborators

* Emily Parker, staff data manager 2022-2024
* Patrick Bills, staff data scientist 2023-2025 [Institute for Cyber-enabled Research (ICER)](https://icer.msu.edu)

## Student Research Assistants
* 2025-
  - Caroline Roche
  - Liz Bauer
  - Vivian Smith
  - Olive Graves
  - Sarah Pecis
  - Addison Hoddinott
  - Elliot Palmer
  - Jamie Soehl
* 2024
  - India Hirschowitz
  - Giovanni DePasquale
  - Caroline Roche
  - Ava Fountain
  - Ann Joseph
  - Maddie Andreatta   
* 2023
  - India Hirschowitz
  - Giovanni DePasquale
  - Caroline Roche
* 2022
  - India Hirschowitz
  - Jordan Zapata
  - Elaine Hammond
* 2021-2024
  - Emily Parker
* 2018-2020
  - Erik Ralston
  - Minali Bhatt

## Publications

MSU Undergraduates led the presentation of a research poster at the 
2024 [MSU Undergraduate University Research and Arts Forum](https://urca.msu.edu/uuraf):
*DePasquale, G., I. Hirschowitz, C. Roche, E.G. Parker, P. Bills, P.L. Zarnetske. April 2024. The North American AvianMetaNet. Michigan State University Undergraduate Research and Arts Forum (UURAF). East Lansing, MI. Poster Presentation.*

In Prep: *AvianMetaNetwork: biotic interactions among birds of the continental United States and Canada*, 
Phoebe Zarnetske, Patrick Bills, Kelly Kapsar, Lucas Mansfield, Emily G Parker
Caroline Roche, India Hirschowitz, Giovanni DePasquale, Sara Zonneveld

## Acknowledgements

*Cornell Lab of Ornithology: Birds of The World, and especially insights from Brian Sullivan and Pam Rasmussen.

*MSU undergraduates listed above


## References

Belmaker, J., P. Zarnetske, M.-N. Tuanmu, S. Zonneveld, S. Record, A. Strecker, and L. Beaudrot. 2015. Empirical evidence for the scale dependence of biotic interactions. Global Ecology and Biogeography 24:750–761. https://doi.org/10.1111/geb.12311

Birds of the World - Comprehensive life histories for all bird species and families. (Accessed January 13, 2022). http://birdsoftheworld.org/bow/home.

Hurlbert, A. H., A. M. Olsen, M. M. Sawyer, and P. M. Winner. 2021. The Avian Diet Database as a source of quantitative information on bird diets. Scientific Data 8:260. https://www.nature.com/articles/s41597-021-01049-9
