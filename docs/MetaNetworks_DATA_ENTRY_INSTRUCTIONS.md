# <code style="color : red">The MetaNetworks Project</code>: 
## Instructions for Data Entry in <code style="color : red">The MetaNetworks Project</code> in L0 subdirectory

From the [Spatial and Community Ecology Lab (SpaCE Lab)](https://www.communityecologylab.com)

https://github.com/TheMetaNetworksProject/MetaNetworksProject-Main


Refer to the main [documentation (readme)](../readme.md) file in the parent directory of this repository for information about the Workflow and subdirectory naming conventions.


## OVERVIEW
Data entry & checking on species interactions occurs within this 
L0 portion of our private, in-progress data repository : [MetaNetworksProject-Working](https://github.com/TheMetaNetworksProject/MetaNetworksProject-Working). 

Only use GitHub or Google Sheets for data entry and editing of files.
*Do not use Microsoft Excel* for data entry or any editing of files;
it has text encoding that differs from GitHub and Google Sheets.

### The <code style="color : red">MetaNetwork repository data/L0</code> folder contains the following files:

### <code style="color : red">data/L0/metadata</code>
Subfolder containing metadata for several column options, including definitions for those options.

### <code style="color : red">metadata/interactions.csv</code>
Metadata and definitions for interaction types.

### <code style="color : red">metadata/resolutions.csv</code>
Metadata and definitions for taxonomic resolutions.

### <code style="color : red">metadata/taxonomic_groups.csv</code>
Metadata and definitions for taxonomic groups.

### <code style="color : red">metadata/interaction_confidence.csv</code>
Metadata and definitions for interaction confidence keywords.

### <code style="color : red">metadata/life_stages.csv</code>
Metadata and definitions for taxon life stages.

### <code style="color : red">metadata/life_histories.csv</code>
Metadata and definitions for life history keywords.

### <code style="color : red">jointproject_taxalist.csv</code>
Taxa look-up table and assignments for data entry. Contains the updates and assignments of taxa entry progress. (Note: this is contained in a Google Sheet within the private project Google Drive and is periodically updated here). 

## Step 1: Get started in GitHub

The first time you use GitHub, do the following: 

- Sign into GitHub and navigate to: https://github.com//TheMetaNetworksProject/MetaNetworksProject. 

- Install GitHub Desktop (or if you use GitHub command line or github.com, skip this step).

- Clone this entire repository by clicking on the green "Code" button and selecting "Open with GitHub Desktop". Save the location of the repository on your computer (not inside a Google Drive or Dropbox or One Drive folder).

## Step 2: Pull the most recent version of the Database
In GitHub Desktop, select <code style="color : red">MetaNetwork</code>. Click "Fetch origin" to pull the most recent version of the database, which will save it to your GitHub location on your computer (established in Step 1). 

## Step 3: Select a species to work on
Navigate to the Google Drive folder [`SpaCE_Lab_EcologicalNetworks/metanetwork_L0_entry`](https://drive.google.com/drive/u/2/folders/1XFwxLrBDAtoOi_cWz62J8XwBWxFLmQL0?dmr=1&ec=wgc-drive-hero-goto) and open the `JointProject_TaxaList` Google Sheet.

Select a taxa that has not been entered yet, fill in your name or initials with that entry in the "Recorder" column. If you are working on a specific project, ensure that the taxa is included in the target taxa for the project under the **Project_Code** column. Add the date you started this taxa in the **Start_Date** column. If you forget to add a start date, that cell will be highlighted <code style="color : #f4cccc">red</code> as a reminder. Once you claim a taxa, the row is highlighted <code style="color : #fce5cd">amber</code> so that other team members do not start processing the same taxa.


## Step 4: Create new google sheet for this species. 

 - Open the **taxa_in_progress** folder in the google drive folder: **SpaCE_Lab_EcologicalNetworks/metanetwork_L0_entry**. 
 - Make a copy of the **_general_intxn_TEMPLATE Google Sheet**. You can do this by right-clicking on it and selecting "make a copy" which then makes a new file "Copy of _general_intxn_TEMPLATE". If you want to open first, then save a copy you can do that, but you need to tell it to make it in this folder, not in your home folder.
 - Open the copy and rename it for the taxa you are going to work on with your initials at the end, **e.g. Passerina_cyanea_PLZ**.
 - If the view does not freeze the top row, select the top row with the headers, go to “View”, “Freeze”, “Freeze 1 Row”. If your Google Sheet view does not freeze the first 4 columns, select the top row with the headers, go to “View”, “Freeze”, “2 Columns”. Then you can drag the Freeze Column line to cover the next few columns so that the first 4 columns are frozen.
 - The sheet is now ready to enter data into, using Google Sheets (not Excel).

The entry sheet is a Google Sheets file with several tabs (unique sheets built into the workbook). In Google Sheets, the bottom bar displays these tabs. The first tab, titled **entry** is the <u>only one you should edit</u>. Each of the other tabs are locked, and will display a warning if you try to edit in them. If this warning pops up, **you are in the wrong tab and should click “cancel”** before locating the proper entry sheet. The locked tabs provide some helper code that support a system called *dynamic dependent dropdowning*, where some of the sheet options depend on information in other cells. It also allows the options for several columns, such as interaction types, to be automatically updated from a single metadata sheet. This allows sheets that are actively being worked on to automatically update if new dropdown options are added. Note that this causes issues if you need to add or delete rows. See the **Extra Notes** section under Step 6 for guidance on this. **The following steps should all be taken on the “entry” sheet only**.

## Step 5: Locate a source

Currently, there are slightly different workflows for locating sources depending on what taxonomic group your target taxon belongs to. This is due to disparities in information databases for different groups: birds have a wealth of collected literature, while plants and fungi have relatively little. As we find more potential databases, we will update the instructions accordingly. Additionally, if you have any recommendations for databases for other taxa, please bring them to us!

For now, use the following steps to locate sources:

a) **If your taxon is a bird**: 
 - i) Go to [Birds of the World Online](http://ezproxy.msu.edu/login?url=https://birdsoftheworld.org) (BOW, via the MSU Library electronic resource portal if you’re off campus). This is the source of natural history information for each bird species entered into the database
 - ii) FIRST **ensure you save the references**. Navigate to the "References" page of the species account (usually the last page on the left-hand menu of the account). Make sure "Order of Appearance" is selected (not Alphabetical). In the browser on the References page, with a Mac: go to File - Save As - HTML or Page Source (for Mac); or with Windows: Right-click on the page (make sure you are not clicking on a link), and "Save As" "Webpage - HTML Only". You will save a single References HTML file containing all of the references for your chosen species to the Google Drive location: `metanetwork_L0_entry/database_refs/`. Save the file as: "Genus_species_bow_refs_VERSION". for "VERSION" replace with the last value in the species account doi. For example, for Northern Flicker, the BOW references filename would be: `Colaptes_auratus_bow_refs_bow.norfli.02.1.html`
 - iii) In general, the best approach to entering the species' data is to open the BOW species account and just skim through it page by page (section by section, in order) for capitalized species names (often Common Names) and italicized species names (often Genus species); this should catch nearly all the entries and will add new ones we missed before. You may see other plain text terms like "passerines" or "corvids" and these refer to entire groups of species in an interaction - these are still important to record and should not be skipped.
 - iv) Note that the website contains a table of contents with different sections (Introduction, Systematics, Behavior, etc.). Please look through ALL SECTIONS to be sure we catch all interactions with other birds because other sections can contain them also.
 - v) After entering all the interactions from BOW, proceed to a primary literature search (part C of this step). **BOW-specific instructions from now on will be indicated with the bird emoji:** 🐦

b) **If your taxon is a non-bird animal**:
  - i) Try searching your taxon on [Animal Diversity Web](https://animaldiversity.org/) (ADW, free to access). This site contains BOW-like species accounts for other animals, though it is not particularly thorough and many species are missing. 
  - ii) FIRST **ensure you save the references**. ADW references are located at the bottom and not on a separate page, so save the html of the whole species account. In the browser on the References page, with a Mac: go to File - Save As - HTML or Page Source (for Mac); or with Windows: Right-click on the page (make sure you are not clicking on a link), and "Save As" "Webpage - HTML Only". You will save a single References HTML file containing all of the references for your chosen species to the Google Drive location: `metanetwork_L0_entry/database_refs/`. Save the file as: "Genus_species_adw_refs". For example, for Rough-skinned Newt, the BOW references filename would be: `Taricha_granulosa_adw_refs.html`
  - iii) Similar to BOW, skim through the ADW page and look for italicized species names, though be careful as there are many plain text terms (like “crabs”) that should not be skipped.
  - iv) After entering all the interactions from ADW, proceed to a primary literature search (part C of this step). **ADW-specific instructions from now on will be indicated with the whale emoji:** 🐳

c) **If your taxon is NOT an animal OR if you have already checked/entered data from BOW or ADW**:
  - i) Perform a **Google Scholar Advanced Search** to identify primary literature and other sources online. Navigate to [**Google Scholar**](https://scholar.google.com).
  - ii) Navigate to the Settings by selecting the 3 horizontal lines at the upper left of the page. Click on **Settings**. Select **Languages** and click the option that says "Search only for pages written in these languages." Check "English."
  - iii) Navigate to the Advanced Search by selecting the 3 horizontal lines at the upper left of the page. Click on the **Advanced Search**. Into the cell next to **Find articles with all of the words** paste all the species current and past names for both Common and Scientific names (see the BOW account section "Systematics History" to find these names), in quotes, separated by OR. *If you have questions about the alternative or former names of the species, please consult with the lab before conducting the search since the Systematics History section of accounts can be confusing*. 
    - Note that you do not have to add subspecies to the search string. 
    - Note  that capitalization doesn't matter and neither do hyphens (i.e., "Brown-hooded parrot" will return the same results as "Brown hooded parrot"). Also, if you leave off OR, it will be interpreted as AND, requiring all of the text strings to appear in the search result.
    - **EXAMPLE: "Pyrilia haematotis" OR "Brown-hooded parrot"** - [this search yielded 216 results](https://scholar.google.com/scholar?as_q=&as_epq=&as_oq=%22Brown+hooded+parrot%22+%22Pyrilia+haematotis%22&as_eq=&as_occt=any&as_sauthors=&as_publication=&as_ylo=&as_yhi=&hl=en&as_sdt=0%2C23).
      - IMPORTANT: Do NOT forget the quotes or the "OR"
      - *If this does not turn up any results, try searching just Common or Scientific name separately.*

  
  - iv) Press Enter or the Search icon to the right of the search bar. This will return a set of papers and other reference literature.
    - *IMPORTANT: If nothing results from this more involved search, check how Google Scholar is coding your search in the searchbar - sometimes it adds "AND" "OR" many times between words, which is incorrect. Click on Advanced Search to see how it is coding your search - fix any errors.*
  - v) Once the search returns results correctly, open [Zotero](https://www.zotero.org/). Zotero is a website and desktop app for organizing sources in research projects, which we are employing to avoid double-checking sources. Locate the [`MetaNetworks_SpaCELab` library](https://www.zotero.org/groups/6598963/metanetworks_spacelab/library), which contains all sources which have been checked or are being checked by other lab members.
  - vi) After locating a potential source from Google Scholar, quickly enter a portion of the title into the search bar in the Zotero library. If the source appears, this means another lab member has already checked it and you can safely skip that source.
  - vii) If the source is not located in the library, it means it is unchecked. Add it to the library. To do this, make sure you have the **Zotero Connecter** web plugin installed. Click on the "Cite" button under the source on the Google Scholar results page, and then click "RefMan" which will connect with Zotero. Ensure you are "Saving to `MetaNetworks_SpaCELab`". This will add it and all the information directly to the Zotero Library!
  - viii) Once you add a source to the library, locate it in Zotero and click on the "Notes" page that appears on the popup table to the right. Add a note that reads **"in progress"**
  
  - ix) After adding to Zotero, click on the potential source in order and navigate to the text (you may have to click on "All Versions" below the source to find a PDF or accessible link). Search in the text for the species to find where it is mentioned, and record interactions into the entry sheet.

  - x) **Instructions specific to primary literature from now on will be indicated with the green book emoji:** 📗

## Step 6: Data entry in the Species sheet

See **_general_intxn_EXAMPLE** in the **taxa_in_progress** folder in Google Drive for an example entry with some commentary about the entry decisions.

Enter interactions for the species you selected by designating the selected species in "taxa1_scientific" and "taxa1_common" in your file, and the species it interacts with in "taxa2_scientific" and "taxa2_common". Refer to the metadata files for rules about how to enter each column, and the information below:

The entry sheet columns are color-coded based on the general type of information they carry. 
- <code style="color : #31cae6">Light blue columns contain taxonomic information.</code>
- <code style="color : #f1c955">Yellow columns contain information about the nature of the interaction, such as the type, effect and taxa life stages.</code> 
- <code style="color : #946bf1">Purple columns contain information about the setting.</code> 
- <code style="color : #fff2c">Gray columns contain administrative information, such as the source and recorder.</code> 

The columns are described below based on the order we feel makes the most sense to complete them in.

### <code style="color : #fff2c">source_citation</code>
- Add the citation of your source to the <code style="color : #fff2c">source_citation</code> column. 
  - 🐦 For BOW, this is found at the bottom of each BOW page (simply copy-paste it); it's the same citation for the entire account.
  - 🐳 For Animal Diversity Web, the citation is located in a thin bar along the bottom of the page that starts with "To cite this page...". Do not include the line with "Last updated:"
  - 📗 For primary literature (i.e. Google Scholar), use the MLA style citation. You can find this by clicking "Cite" under the source on the Google Scholar Results page.

### <code style="color : #fff2c">source_URL</code> 
- *Important:* you need to copy-paste the full URL for each URL page that has the source(s) of the interaction into the <code style="color : #fff2c">source_URL</code> column.
- Do not add multiple URLs to a single cell. Each row should reflect the unique information derived from a source and its URL, and text excerpt combination.
  - 🐦 Separate URLs are entered in separate rows if there are multiple BOW pages with information on the same interaction (e.g., “behavior” and “Introduction” pages for example). A full BOW URL looks like this so that “behavior” is visible: https://birdsoftheworld-org.proxy2.cl.msu.edu/bow/species/gofwoo/cur/behavior.
  - 🐦 You can also cite pictures and videos featured in the articles! If possible, get the direct link by right-clicking the image/video, or clicking on the image and following the highlighted link (it will usually be from Macaulay Library or eBird). If there is no direct URL, you may use the URL for the BOW page it was found on. For the note, copy any descriptions used in BOW about the image/video, or write a brief description about it.
  - 📗 When copying URLs from sources gathered from Google Scholar, ensure that the link you provide is the same as the one referenced in the database search page. Scrolling through a PDF on certain libraries can add additional queries to the URL, creating a mismatch when referencing the source in the future. To ensure that you are copying the URL as presented on the database, right-click on the hyperlink and select "Copy link address" before pasting into the <code style="color : #fff2c">source_URL</code> column.
  

### <code style="color : #fff2c">timing_location_excerpt</code> 
- Enter the text excerpt containing information about the context of the interaction observation (e.g. time of year, year, location, etc.) into the <code style="color : #fff2c">timing_location_excerpt</code> column. 
- These excerpts may consist of an entire paragraph or more. For example, the start of a paper may discuss the time of year and country, while a later paragraph might mention a more specific locality where an observation was observed. Ensure that you copy-paste the section heading of the paragraph (i.e. "Introduction" or "Life-History" or "Habitat: Breeding Habitat"), then copy-paste the text that includes the interaction. 
- You may have several rows with the same excerpts because there are many interactions that were observed at the same site.

### <code style="color : #fff2c">interaction_excerpt</code>
- Enter the text excerpt containing information about the nature of the interaction (e.g. taxa involved, description of interaction) into the <code style="color : #fff2c">interaction_excerpt</code> column.
- These excerpts may consist of an entire paragraph or more. For example, the start of a paper may discuss the time of year and country, while a later paragraph might mention a more specific locality where an observation was observed. Ensure that you copy-paste the section heading of the paragraph (i.e. "Behavior: Agonistic Behavior" or "Life-History" or "Feeding: Diet"), then copy-paste the text that includes the interaction. 
- You may have several rows with the same excerpts because there are many pairwise interactions that were recorded in the same passage of text.
- The <code style="color : #fff2c">timing_location_excerpt</code> and <code style="color : #fff2c">interaction_excerpt</code> might also be identical if there is a passage that encompasses the context and nature of the interaction.

### <code style="color : #31cae6">taxa1_scientific</code>, <code style="color : #31cae6">taxa2_scientific</code>

- Enter the binomial scientific names (*Genus species*) of the species involved in the interaction into these columns.
- Recall that the taxa1 should be your focal taxon selected from <code style="color : red">jointproject_taxalist.csv</code>. Taxa2 are interacting taxa found in the text.
- Usually the scientific names of species are italicized in the paper or database, and should be entered **exactly as written** into the datasheet. 
- **IMPORTANT**: You will likely come across interactions between taxa that are NOT your focal taxa. For example, if your focal taxon was the Great Blue Heron, you might come across a source detailing the diets of all heron species in North America. In this case, you should record all interactions in order to fully check the source. You may select either taxon to be taxa1 and taxa2.
- You may come across one of several rare cases for a species scientific name in the text:
  - On occasion, you may only be able to find a common name for a taxon referenced in the text (e.g., Yellow Warbler). In these cases, look up the scientific name (*Genus species*).
  - If a specific subspecies is mentioned in reference, then include in the scientific name (*Genus species subspecies*).
  - If the article addresses a bird as *Genus subspecies* rather than *Genus species subspecies* (e.g. *Mimus orpheus* instead of *Mimus polyglottos orpheus*), look up the full three-word name of the subspecies and enter that into the appropriate scientific name column.
  - If the article uses characters from scripts outside of the English alphabet (e.g. æ, Ø, or Þ), copy paste into the species column exactly as written. When exporting to CSV, double-check that the character looks the same.
  - If the article does not mention a specific species but does reference a group (e.g. "corvids", "gulls", etc.), then enter taxa2 as an unidentified species. For scientific name, use the smallest taxonomic group that captures all members of that group. For example, "corvids" would be entered into <code style="color : #31cae6">taxa2_scientific</code> as "*Corvidae* sp.". Ask an experienced lab member if you are unsure how to do this.

### <code style="color : #31cae6">taxa1_common</code>, <code style="color : #31cae6">taxa2_common</code>
- Enter the primary English common name of the species involved in the interaction into these columns.
- Recall that the taxa1 should be your focal taxon selected from <code style="color : red">jointproject_taxalist.csv</code>, and the common name should be copied from that sheet exactly. Taxa2 are interacting taxa found in the text.
- Usually the common names of species are capitalized in the paper or database, and should be entered **exactly as written** into the datasheet.
- - You may come across one of several rare cases for a species common name in the text:
  - If multiple common names are used for a single taxon in the paper, select the first one mentioned or the main one used.
  - If the paper does not mention a common name, you may search the scientific name to figure out the common name. If the species doesn't have a common name, you may leave the cell blank.
  - If the article does not mention a specific species but does reference a group (e.g. "corvids", "gulls", etc.), then enter taxa2 as an unidentified species. For the common name, use "unid." + group mentioned. For example, "corvids" would be entered as common name "unid. corvid" into <code style="color : #31cae6">taxa2_common</code>. Ask an experienced lab member if you are unsure how to do this.

### <code style="color : #31cae6">taxa1_resolution</code>, <code style="color : #31cae6">taxa2_resolution</code>
- These columns contain dropdowns with several taxonomic resolution levels (i.e. Kingdom, Family, Genus). Select the finest level resolution that taxa1 and taxa2 fall under. For the most part this will be species, but some taxa may be at broader or finer resolutions.
- If you are unsure what resolution your taxa falls under, check with an experienced lab member.
- If you need a refresher on what these terms mean, check the <code style="color : red">metadata/resolutions.csv</code>

### <code style="color : #31cae6">taxa1_group</code>, <code style="color : #31cae6">taxa2_group</code>
- These columns contain dropdowns with the names of colloquial "groups" of organisms. For the most part, these are at kindgom level (*plant*, *fungus*, *archaea*, *protist*, *bacteria*), but the animals are broken down further into *invertebrate*, *reptile*, *amphibian*, *fish*, *bird* and *mammal*.
- Indicate, for each species, which of these groups taxa1 and taxa2 fall under. If you are unsure, discuss with an experienced lab member.
- Be very careful that you select the correct groups here. These determine the dropdown options for future columns, so selecting the wrong group could cause later issues.
- Each organism should fall into one of these groups, and therefore you should only select options available in the dropdown. If you enter another value, the cell will be flagged, indicating a potential mistake.
- If you need a refresher on what these terms mean, check the <code style="color : red">metadata/taxonomic_groups.csv</code>

### <code style="color : #f1c955">interaction</code>
- This column contains a dropdown with a list of potential interaction types based on the entries in the group columns. If nothing appears in this column, or the interactions look incorrect, check your entries in <code style="color : #31cae6">taxa1_group</code> and <code style="color : #31cae6">taxa2_group</code>.
- Enter in the appropriate interaction type, based on information from the text.
- Entering a value not on the dropdown list will pop up with a warning in that cell, which is usually caused by a typo. It is possible you will need to enter a value not on the list. For example, you may have "competition-" over a resource not defined in the interactions, or find a new interaction that has yet to be defined in the list. In this case, you may ignore the warning. 
- If you need a reminder about the interaction options, check <code style="color : red">metadata/interactions.csv</code>

### <code style="color : #f1c955">effect_tx1_on_tx2</code>, <code style="color : #f1c955">effect_tx2_on_tx1</code>
- These columns contain dropdowns with options of -1, 0 and 1. These are the impacts that an interaction has on each species, with 1 indicating beneficial interactions, -1 indicating harmful interactions and 0 indicating neutral interactions.
- Each interaction type has a specific set of effects, which are defined in <code style="color : red">metadata/interactions.csv</code>.
- In these columns, you must enter either -1, 0, or 1, as entering another value will cause the sheet to error. Be careful to place the correct value in the effect columns.   

### <code style="color : #f1c955">interaction_confidence</code>
- This column contains a dropdown with three options relating to the confidence in the interaction.
- Enter **weak** if the description is vague, mentions that it is a “possible” or "likely" (but not observed) interaction, rare interaction, or inferred interaction. 
- Enter **strong** if the interaction was observed, or was strongly stated (i.e., "species 1 often found competing with species 2").
- Enter **artificial** if the interaction was non-natural. For example, an experimental setup was used to observe a species of monkey eating eggs from the nest of a bird.

### <code style="color : #f1c955">taxa1_lifestage</code>,  <code style="color : #f1c955">taxa2_lifestage</code>
- These columns contain dropdowns with options for organismal life stages based on the groups each taxa falls into.
- Enter the lifestage appropriate to the interaction, per taxa. 
- It may differ between the two taxa or be the same. For example, with Brood Parasites, the interactions involved include BOTH adult and nestlings. The options for this dropdown will vary based on the taxon’s group. 
- If nothing appears in these columns, or the life stages look incorrect, check your entries in <code style="color : #31cae6">taxa1_group</code> and <code style="color : #31cae6">taxa2_group</code>.
- Be sure to check <code style="color : red">metadata/life_stages.csv</code> for definitions.


### <code style="color : #f1c955">taxa1_life_history_season</code>,  <code style="color : #f1c955">taxa2_life_history_season</code>
- These columns contain dropdowns with options for life history seasons that the interaction takes place during.
- Enter the life history timing of the interaction for each taxa (year-round, migration, breeding, non-breeding). For example, if the interaction occurs during the non-breeding season (typically winter), indicate "non-breeding". 
  - 🐦 If the article mentions a month, you can check if it occurs during taxa1 breeding season using the phenology diagram (usually on the Introduction or Breeding page), or reading the Breeding page (the middle ring in the diagram in the breeding period). 
- These options are available from a dropdown, and if the interaction occurs throughout multiple seasons, select multiple. If it occurs year-round, only select that option. 
- Be sure to check <code style="color : red">metadata/life_histories.csv</code> for definitions.

### <code style="color : #946bf1">time_of_year</code>
- Enter the time of year that the interaction occurs in. 
- If the interaction occurs year-round, use enter **"year-round"**. Otherwise, enter the full English names of the months during which the interaction occurred. For example, **"march"**. 
  - If the interaction is not year-round but occurs across multiple months, indicate the starting and ending month with a dash. For example, if an interaction occurs in August, September, October, November and December, enter **"august-december"**.
  - If the interaction occurs during disjointed periods, separate each period with a semicolon. For example, if an interaction occurs in May, June, November and December, enter **"may-june; november-december"**.

### <code style="color : #946bf1">year</code>
- Enter the year that the interaction was observed in the study. 
- *Note: this may differ from the year the study was published*.
- If the interaction was observed across multiple years, indicate their start and end year with a dash. For example, if a study recorded an interaction each year from 2003 to 2007, enter **"2003-2007"**.
- If the interaction was observed in disjointed years, separate the periods with a semicolon. For example, if an interaction was observed in 2003, 2004, 2005 and 2007, enter **"2003-2005; 2007"**.

### <code style="color : #946bf1">elevation</code>
- If given, enter the elevation of the interaction record. 
- Only enter a number, do not attach a unit. To standardize this, please enter the value in meters (convert feet to meters if necessary. 1 foot is 0.3048 meters.)

### <code style="color : #946bf1">latitude</code>
- If listed, give the latitude of the location where the interaction occurred. 
- For standardization, please list this in degree format (i.e. 38.889469), meaning you may have to convert if the value is given in Degrees-Minutes-Seconds notation (i.e. 38° 53′ 22.09″ N)
  - You can use [this calculator tool](https://applications.pgc.umn.edu/convert/) to make the conversions easier!

### <code style="color : #946bf1">longitude</code>
- If listed, give the longitude of the location where the interaction occurred. 
- For standardization, please list this in degree format (i.e. -77.035258), meaning you may have to convert if the value is given in Degrees-Minutes-Seconds notation (i.e. 77° 2′ 6.93″ W).
  - You can use [this calculator tool](https://applications.pgc.umn.edu/convert/) to make the conversions easier!

### <code style="color : #946bf1">location</code>
- To the finest level you can identify, give the location of the interaction. 
- This should be a proper name. Examples may include:
  - a city (e.g. El Paso, TX)
  - a settlement (e.g. Dayuma, Orellana)
  - a park (e.g. Yosemite National Park, CA)
  - a county (e.g. Clark County, WA). 
- As in the above examples, please include the name or abbreviation of a subdivision (i.e. state or province) where applicable. This will help differentiate between similarly named places within large countries (for example, there are many locations called “Springfield” in the United States). 
- Do not give specific ‘directions’ to the location (i.e. 4 miles west of the northern tip of the Tiputini River).

### <code style="color : #946bf1">country</code>
- Provide the English name of the modern day country where the interaction was observed. 
- This may take some further research if the interaction occurred in a country that no longer exists or was renamed. 
  - For example, for an interaction recorded in “Zaire”, the country should be listed as the Democratic Republic of the Congo.
  - For an interaction recorded in “the Soviet Union”, check the location to determine what modern country the interaction was recorded in (for some former countries, like the Soviet Union, there may be several options).

### <code style="color : #fff2c">recorder</code> 
- Enter your name or initials in this column for each row in which you entered the interaction data.

### <code style="color : #fff2c">entry_date</code> 
- Enter the date (mm/dd/yyyy) during which you filled out each row in this column.

### <code style="color : #fff2c">entry_changes</code> 
- Do not enter anything into the entry_changes column. This will be used by reviewers when checking your sheet, if any changes are made.

### <code style="color : #fff2c">notes</code> 
- The notes column is a space to enter any additional notes you would like. It will not be systematically used, but feel free to use it as scratch or for personal notes. 

### <code style="color : #fff2c">version</code> 
- The version column should not be touched. It will automatically update with the version number when values are entered in the row.

### Extra Notes

**Data Entry Tools**
- As mentioned above, the entry sheet uses several auxiliary tabs to manage the *dynamic dependent dropdowning* that enables the options in each column and prevents errors. This system works well if the the rows stay static, but adding or deleting rows can cause issues with the syncing.
- To deal with this, we built a set of data entry tools into the Google Sheet, which can be accessed from the **Data Entry** menu at the top of the sheet.
- If you need to **insert a row**, select the row above where you want the new row to be inserted, and click the "Add new row" function.
- If you need to **delete a row**, select the row for deletion and click the "Delete current row" function. 
- If you ever make a mistake that causes the sheet to de-sync, select the "Repair all rows" function. This takes a while to run and should thus be used sparingly. 
- The first time you use these functions, you might need to give AppsScript permission to run from your Google account.

**Multi-species interactions**
- If you find a description that lists > 2 species involved in an interaction (e.g., mixed flock, aggregate foraging, competing over same resource), then enter in all pairwise interactions into the same google sheet.

**Abbreviations and Codes**
- If you encounter a 4-letter banding abbreviation (e.g. GHOW) or other acronym or code for mentioning a taxa, copy and paste the text excerpt where the abbreviation is defined (e.g., "Great-horned Owl (GHOW)...") into the text_excerpt columns in every row where an interaction was derived from a text excerpt that includes an abbreviation.

**Pairwise interactions**
- Note that for taxa_1, its interaction with taxa_2 will become part of taxa_2's pairwise interactions. NOTE: if a duplicate entry occurs, it’s ok (we will edit in R). It takes too much time to avoid duplicates by manually searching for the taxa_2 entries that already exist.

**Co-occurrence**
- Co-occurrence is a weak "interaction" where two species are observed in the same location at the same time, with no specific interaction between them observed. We used to record this into the sheet, but to save time we now ignore these unless a more specific interaction is described.

## Step 7: Export/Download to CSV

When you've completed entering the all interactions in your Google Sheet, it needs to be incorporated into the collection of species files in GitHub.

1) First, indicate that you finished the species by entering the date into the **End_Date** column of the relevant row in the `JointProject_TaxaList` sheet. This should turn the row <code style="color : #d9ead3">green</code>, indicating it has been complete

2) Then, move your sheet from  **SpaCE_Lab_EcologicalNetworks/metanetwork_L0_entry/taxa_in_progress** to  **SpaCE_Lab_EcologicalNetworks/metanetwork_L0_entry/taxa_complete**. You can do this by using the "move" option within the sheet, or by cutting and pasting your sheet from one folder to the other.

3) Next, export your spreadsheet to CSV, which downloads it to your desktop. **Ensure you are downloading the "entry" sheet and not the other tabs**.

4) You will most likely need to rename the CSV file that's downloaded to your computer. Name it for the species and add your initials, e.g. **Passerina_cyanea_PLZ.csv**.    

## Step 8: Upload CSV to GitHub 

1) Open the <code style="color : red">repository</code> and navigate to the <code style="color : red">data/L0/taxa_to_check</code> folder. Click the **[Add file]** button. That button has two choices, select "Upload files".   

2) You may drag the CSV file, or click the "choose your files" option to select it. 

3) In the form below where is says "commit changes", type in a message indicating the file is ready to be checked: e.g., 
  `Passerina_cyanea_PLZ.csv ready for checking`   

4) If there is anything that has happened that you need to note (e.g., you weren't able to complete all rows, or there is some data issue you can't overcome, add that to the "optional extended description" box. Most likely you won't need this, but it's there to communicate anything about this file that you need to. 

5) Leave the option "Commit directly to the main branch" selected.

6) Click the green "commit changes".

## Step 9: Entry checking

All taxa files in the <code style="color : red">data/L0/taxa_to_check</code> folder are processed with a script that checks for invalid entries and logical errors, such as a negative year or a misspelled month. Taxa with no issues are passed into the <code style="color : red">data/L0/taxa_checked</code> folder and incorporated into the larger dataset.

If the script flags the taxa sheet, it is sent to the <code style="color : red">data/L0/flagged_taxa</code> folder for checking.

## Step 10: Manual checking

Reviewers will check all sheets that are placed in <code style="color : red">data/L0/flagged_taxa</code>. The script will add a <code style="color : red">flagged_issue</code> to indicate the problem row, and a short description of what the error is. 

Reviewers will open the CSV and adjust the issues in the sheet as necessary, leaving an annotation of the changes with their initials and the date in the `entry_changes` column. The sheet can be moved back to the <code style="color : red">data/L0/taxa_to_check</code> folder, and passed through the checking script again.

