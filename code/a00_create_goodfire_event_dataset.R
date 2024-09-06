
# This script will create a set of polygons to use for the good fire project. It combines MTBS and combined wildland fire polygons

library(tigris)
library(httr)
library(jsonlite)
library(sf)
library(tidyverse)





# FUNCTIONS ----

# Function to access MTBS conus polygons
access.data.mtbs.conus <- function() {
  mtbs <- glue::glue(
    "/vsizip/vsicurl/",
    "https://edcintl.cr.usgs.gov/downloads/sciweb1/shared/MTBS_Fire/data/composite_data/burned_area_extent_shapefile/mtbs_perimeter_data.zip",
    "/mtbs_perims_DD.shp") |>
  sf::st_read()
  return(mtbs)
}


# Function to access Welty & Jeffries combined wildland fire polygons
access.data.welty.jeffries <- function() {
  #Write out the URL query
  baseUrl <- "https://gis.usgs.gov/sciencebase3/rest/services/Catalog/61aa537dd34eb622f699df81/MapServer/0/query"
  queryParams <- list(f = "geojson",
                      where = "1=1",
                      outFields = "*",
                      returnGeometry = "true")
  response <- httr::GET(url = baseUrl, query = queryParams)
  
  #Request data
  welty <- get_all_from_arcgis_rest_api(baseUrl, queryParams, 1000)
  return(welty)
}

t <- access.data.welty.jeffries()




get_all_from_arcgis_rest_api <- function(base_url, query_params, maxRecord) {
  # Initialize variables
  total_features <- list()
  offset <- 0
  
  repeat {
    # Update the resultOffset parameter in query_params
    query_params$resultOffset <- offset
    
    # Make the GET request using the base URL and query parameters
    response <- GET(url = base_url, query = query_params)
    
    # Check if the request was successful
    if (status_code(response) == 200) {
      # Read the GeoJSON data directly into an sf object
      data <- st_read(content(response, as = "text"), quiet = TRUE)
      
      # Append the data to the list of features
      total_features <- append(total_features, list(data))
      
      # Break if the number of records fetched is less than the maxRecord, indicating the last page
      if (nrow(data) < maxRecord) {
        break
      }
      
      # Increment the offset by the maximum number of records for the next page
      offset <- offset + maxRecord
    } else {
      # Handle errors and provide meaningful messages
      error_message <- content(response, "text", encoding = "UTF-8")
      stop("Failed to fetch data: ", status_code(response), " - ", error_message)
    }
  }
  
  # Combine all pages into one sf object
  all_data_sf <- do.call(rbind, total_features)
  
  return(all_data_sf)
}








#A function to get all of the data from ArcGIS REST API for a given request (i.e. avoiding request thresholds)
# PARAMETERS
# url :: a complete URL request query to an ArcGIS REST dataset
# maxRecord :: the maximum records that can be returned from the API
# Written with assistance from ChatGPT 4.0
get.all.from.arcgis.rest.api <- function(url, maxRecord) {
  # Initialize variables
  total_features <- list()
  offset <- 0
  
  repeat {
    # Construct the URL with offset
    paged_url <- paste0(url, "&resultOffset=", offset)
    
    # Fetch the data
    response <- GET(paged_url)
    
    # Check if the request was successful
    if (status_code(response) == 200) {
      data <- sf::st_read(content(response, "text"), quiet = TRUE)
      total_features <- append(total_features, list(data))  # Append data
      
      # Break if the data fetched is less than the max count, indicating the last page
      if (nrow(data) < maxRecord) {
        break
      }
      offset <- offset + maxRecord  # Increase offset for the next page
    } else {
      stop("Failed to fetch data: ", status_code(response))
    }
  }
  
  # Combine all pages into one sf object
  all_data_sf <- do.call(rbind, total_features)
  
  return(all_data_sf)
}



#Function to write a shapefile to a new, file-specific directory and add a zipped version
#    shp = the sf file to write to shapefile
#    location = path of directory to create the new file-specific subdirectory in
#    filename = name of file WITHOUT .shp
#    zipOnly = TRUE / FALSE, should the original (unzipped) files be removed?
#    overwrite = TRUE / FALSE, should files be overwritten?

# Example use:
# st_write_shp(shp = prepped_for_parks_etal,
#              location = here("data/derived"),
#              filename = "career_lba_for_parks_v1",
#              zipOnly = TRUE,
#              overwrite = TRUE)
st_write_shp <- function(shp, location, filename, zipOnly, overwrite) {
  
  #Check for required packages and install if not installed, then load
  list.of.packages <- c("zip","sf","here")
  new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
  if(length(new.packages)) install.packages(new.packages)
  library(zip)
  library(sf)
  library(here)
  
  
  
  #Create subdirectory & manage overwriting
  zipOnlyFile <- here::here(location, glue::glue("{filename}.zip"))
  outDir <- here::here(location, filename)
  
  if(!zipOnly & dir.exists(outDir) & overwrite) {
    unlink(outDir, recursive = TRUE)
  } else if (!zipOnly & dir.exists(outDir) & !overwrite) {
    stop("Directory already exists")
  }
  
  if(zipOnly & file.exists(zipOnlyFile) & overwrite) {
    unlink(zipOnlyFile)
  } else if (zipOnly & file.exists(zipOnlyFile) & !overwrite) {
    stop("Zip file already exists")
  }
  
  
  if (!dir.exists(outDir)){
    dir.create(outDir)
  }
  
  
  
  #Write file
  sf::st_write(shp,
               here::here(outDir, paste(filename, ".shp", sep = "")),
               append = FALSE) #overwrite
  
  #Get all shapefile components
  allShpNms <- list.files(here::here(outDir),
                          pattern = paste(filename, "*", sep = ""),
                          full.names = TRUE)
  
  
  #Zip together
  zipfile <- here::here(outDir, paste(filename, ".zip", sep=""))
  zip::zip(zipfile = zipfile,
           files = allShpNms,
           mode = "cherry-pick")
  
  
  #Remove raw files if desired
  if(zipOnly == TRUE) {
    file.copy(zipfile, zipOnlyFile)
    unlink(here::here(outDir), recursive = TRUE)          
  }
  
}



create.combined.event.set <- function(earliestYear, latestYear) {
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
    dplyr::select(DatasetID, Dataset, Fire_Year)
  
  ## MERGE & WRITE ----
  allFiresInterest <- rbind(mtbsInterestWF, weltyInterestWFSub1000) |>
    dplyr::mutate(GoodFireID = paste0("GF_", dplyr::row_number()))
  
  
  derivedDatDir <- here::here('data', 'derived')
  if(!dir.exists(derivedDatDir)) {
    dir.create(derivedDatDir)
  }
  
  flNm <- paste("goodfire_dataset_for_analysis", earliestYear, latestYear, sep = "_")
  
  sf::st_write(allFiresInterest, here::here(derivedDatDir, paste0(flNm, ".gpkg")), append = FALSE)
  st_write_shp(shp = allFiresInterest,
               location = here::here('data', 'derived'),
               filename = flNm,
               zipOnly = TRUE,
               overwrite = TRUE)
}

# OPERATE ----

epsg <- "EPSG:5070"


westernStates <- c("WA", "OR", "CA", "ID", "NV", "MT", "WY", "UT", "CO", "AZ", "NM")
west <- tigris::states() |>
  dplyr::filter(STUSPS %in% westernStates) |>
  sf::st_transform(epsg)



## Access data
welty <- sf::st_read(here::here('data', 'raw', 'welty_combined_wildland_fire_dataset', 'welty_combined_wildland_fire_perimeters.shp')) |>
  sf::st_transform(epsg)

welty <- access.data.welty.jeffries()










mtbsFile <- here::here('data', 'raw', 'mtbs_perims.gpkg')
if(!file.exists(mtbsFile)) {
  mtbs <- access.data.mtbs.conus()
  sf::st_write(mtbs, mtbsFile)
} else {
  mtbs <- sf::st_read(mtbsFile)
}
mtbs <- mtbs |>
  sf::st_transform(epsg)

unique(mtbs$Incid_Type)


# Use operational function
create.combined.event.set(earliestYear = 2010, latestYear = 2020)
create.combined.event.set(earliestYear = 1990, latestYear = 2020)





