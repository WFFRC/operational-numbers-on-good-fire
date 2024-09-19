
# This script will create a set of polygons to use for the good fire project. It combines MTBS and combined wildland fire polygons

rm(list = ls())

#This code section loads a personal utilities package (tlmr), and then uses it for package management
if (!requireNamespace("tlmr", quietly = TRUE)) {
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools")  # Install 'devtools' if it's not available
  }
  devtools::install_github('TylerLMcIntosh/tlm-r-utility', force = TRUE)
}
library(tlmr)
tlmr::install_and_load_packages(c("tigris",
                                  "tictoc",
                                  "httr",
                                  "jsonlite",
                                  "sf",
                                  "tidyverse"))


# FUNCTIONS ----

#Operational function to merge the welty & MTBS datasets
create_combined_event_set <- function(earliestYear, latestYear) {
  # WELTY
  #filter to time period and geographic area of interest, add size category
  weltyInterest <- welty |>
    dplyr::filter(Fire_Year >= earliestYear & Fire_Year <= latestYear) |>
    sf::st_filter(west) |>
    dplyr::mutate(SizeCategory = dplyr::case_when(GIS_Acres >= 1000 ~ "Large",
                                                  GIS_Acres < 1000 ~ "Small"))
  
  #Split welty into RX & wildfire
  weltyInterestRx <- weltyInterest |>
    dplyr::filter(Assigned_F == "Prescribed Fire" | Assigned_F == "Unknown - Likely Prescribed Fire")
  weltyInterestWF <- weltyInterest|>
    dplyr::filter(Assigned_F == "Wildfire" | Assigned_F == "Likely Wildfire")
  
  weltyInterestWFSub1000 <- weltyInterestWF |>
    dplyr::filter(SizeCategory == "Small") |>
    dplyr::mutate(Dataset = "Welty", DatasetID = OBJECTID) |>
    dplyr::select(DatasetID, Dataset, Fire_Year)
  
  # MTBS
  
  mtbsInterestWF <- mtbs |>
    dplyr::filter(Incid_Type != "Prescribed Fire") |>
    #dplyr::filter(Incid_Type == "Wildfire") |>
    dplyr::mutate(Fire_Year = lubridate::year(Ig_Date)) |>
    dplyr::filter(Fire_Year>= earliestYear & Fire_Year <= latestYear) |>
    sf::st_filter(west) |>
    dplyr::mutate(Dataset = "MTBS", DatasetID = Event_ID) |>
    dplyr::select(DatasetID, Dataset, Fire_Year) |>
    dplyr::rename(geometry = geom)
  
  
  ## MERGE & WRITE ----
  allFiresInterest <- rbind(mtbsInterestWF, weltyInterestWFSub1000) |>
    dplyr::mutate(GoodFireID = paste0("GF_", dplyr::row_number()))
  
  
  derivedDatDir <- here::here('data', 'derived')
  if(!dir.exists(derivedDatDir)) {
    dir.create(derivedDatDir)
  }
  
  flNm <- paste("goodfire_dataset_for_analysis", earliestYear, latestYear, sep = "_")
  
  sf::st_write(allFiresInterest, here::here(derivedDatDir, paste0(flNm, ".gpkg")), append = FALSE)
  tlmr::st_write_shp(shp = allFiresInterest,
               location = here::here('data', 'derived'),
               filename = flNm,
               zip_only = TRUE,
               overwrite = TRUE)
}


# OPERATE ----

epsg <- "EPSG:5070"

westernStates <- c("WA", "OR", "CA", "ID", "NV", "MT", "WY", "UT", "CO", "AZ", "NM")
#westernStates <- c("CO")

west <- tigris::states() |>
  dplyr::filter(STUSPS %in% westernStates) |>
  sf::st_transform(epsg)



# ## Access data
# 
# #Access welty & jeffries combined wildland fire polygons dataset
# tic()
# welty <- tlmr::access_data_welty_jeffries(bbox_str = tlmr::st_bbox_str(west),
#                                           epsg_n = 5070,
#                                           where_param = "1=1",
#                                           timeout = 40000)
# toc()
# 
# 
# 
# 
# tic()
# t <- tlmr::access_data_welty_jeffries(bbox_str = tlmr::st_bbox_str(west),
#                                           epsg_n = 5070,
#                                           where_param = utils::URLencode("Fire_Year BETWEEN 2010 AND 2020 AND GIS_Acres < 1000 AND (Assigned_Fire_Type = 'Wildfire' OR Assigned_Fire_Type = 'Likely Wildfire')"),
#                                           timeout = 1200)
# toc()
# 
# 
# 
# tic()
# t <- tlmr::access_data_welty_jeffries(bbox_str = tlmr::st_bbox_str(west),
#                                       epsg_n = 5070,
#                                       where_param = utils::URLencode("GIS_Acres<1000"),
#                                       timeout = 1200)
# toc()
# 
# 
# 
# 
# x <- utils::URLencode("Fire_Year BETWEEN 2010 AND 2020 AND GIS_Acres < 1000 AND (Assigned_Fire_Type = 'Wildfire' OR Assigned_Fire_Type = 'Likely Wildfire')")
# 

# The welty & jeffries combined fire polygon dataset can be acquired here: https://www.sciencebase.gov/catalog/item/61aa537dd34eb622f699df81
welty <- sf::st_read(here::here('data', 'raw', 'welty_combined_wildland_fire_dataset', 'welty_combined_wildland_fire_perimeters.shp')) |>
  sf::st_transform(epsg)


#Access MTBS dataset
mtbsFile <- here::here('data', 'raw', 'mtbs_perims.gpkg')
if(!file.exists(mtbsFile)) {
  mtbs <- tlmr::access_data_mtbs_conus()
  sf::st_write(mtbs, mtbsFile)
} else {
  mtbs <- sf::st_read(mtbsFile)
}
mtbs <- mtbs |>
  sf::st_transform(epsg)

unique(mtbs$Incid_Type)


# Use operational function
create_combined_event_set(earliestYear = 2010, latestYear = 2020)
create_combined_event_set(earliestYear = 1985, latestYear = 2020)





