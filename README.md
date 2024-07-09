# a-number-on-good-fire
Good fire in western U.S. forests: estimating the beneficial ecosystem work of wildfires

# Good Fire scripted workflow readme

The good fire repository contains all code necessary to re-create the 'Good Fire' paper by Balch et al.

Scripts are ordered from 00 on up, and are meant to be run in order. Scripts with 'a' after the number manage wildfire event data manipulation and summarization prior to data merge, while scripts with 'b' after the number manage prescribed burn event data manipulation and summarization. Scripts with neither 'a' or 'b' are used after all data are prepared for analysis

Javascript scripts (.js) are meant to be run on Google Earth Engine (GEE), and each also contain a link to the online version of the working script.

A description of all scripts is included below.

## Script descriptions

### Wildfire event manipulation
00a_create_goodfire_event_dataset.R : This script merges data from the MTBS & Welty&Jeffries fire event datasets into a single main dataset
01a ADD THIS SCRIPT NAME cbi : This script generates region-wide CBI layers for the goodfire event dataset
02a ADD THIS SCRIPT NAME streamlined gf : This fire generates good fire layers from the CBI layers derived in the last script and summarizes the data for any set of summary polygons. It also outputs per-event statistics. All outputs go to user's Google Drive
03a_merge_gf_gdrive_data.R : This script pulls outputs from GEE (GDrive) to the user's local machine and merges the annualized data for further use. It also accesses the remote per-event statistics.
04a_summarize_gf_data.R : This script summarizes the good fire wildfire event data at the summarizing polygon and annual levels.

### Prescribed burn event manipulation

00b_prep_rx_for_gee.R : This script prepares NFPORS RX data for use in GEE
01b_add_gee_data_to_rx.js : This GEE script adds Fire Regime Group and landcover data to the prescribed burn event data
02b_merge_rx_data.R : This script pulls in outputs from GEE and merges the new data with the raw spatial NFPORS data. It also cleans the data.
03b_summarize_rx_data : This script summarizes rx data at a given summarizing polygon and annual level.

### Main analysis workflow
00_create_plots.qmd :
01_create_spatial_graphics.qmd :


