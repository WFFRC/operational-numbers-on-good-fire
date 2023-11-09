# Export data to get lcms from GEE at nfpors points
# Tyler L. McIntosh
# CU Boulder CIRES Earth Lab
# Last updated: 11/8/23
# 
# This script uses the following naming conventions wherever possible:
#   lowerCamelCase for variables
# period.separated for functions
# underscore_separated for files


# SETUP ----
## Libraries ----

#Check the required libraries and download if needed
list.of.packages <- c("tidyverse", #Includes ggplot2, dplyr, tidyr, readr, purrr, tibble, stringr, forcats
                      "terra",
                      "sf",
                      "mapview",
                      "here",
                      "future", "future.apply", "furrr", "doFuture", "progressr", #Futureverse!
                      "tictoc", 
                      "mblm", #Median-based linear models (i.e. thiel-sen)
                      "plyr",
                      "scales", #add commas to ggplot axis
                      "tigris", #US data
                      "scales") #add commas to axis
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)

lapply(list.of.packages, library, character.only = TRUE) #apply library function to all packages


## Clean workspace & set up environment ----
rm(list=ls()) #Ensure empty workspace if running from beginning
here::here() #Check here location


#Load data
nfpors <- sf::st_read(here::here('data', 'raw', 'NFPORS_WestStates_2010_2021', 'NFPORS_WestStates_2010_2021.gdb'),
                      layer = "West_NFPORS_2010_2021") %>%
  dplyr::filter(!is.na(ACTUALCOMPLETIONDATE)) #ensure all included burns were actually done


#re-export as shp for GEE

#Function to write a shapefile to a new, file-specific directory and add a zipped version
#    shp = the sf file to write to shapefile
#    location = path of directory to create the new file-specific subdirectory in
#    filename = name of file WITHOUT .shp
#    zipOnly = TRUE / FALSE, should the original (unzipped) files be removed?

# Example use:
# st_write_shp(shp = prepped_for_parks_etal,
#              location = here("data/derived"),
#              filename = "career_lba_for_parks_v1",
#              zipOnly = TRUE)
st_write_shp <- function(shp, location, filename, zipOnly) {
  
  #Check for required packages and install if not installed, then load
  list.of.packages <- c("zip","sf","here")
  new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
  if(length(new.packages)) install.packages(new.packages)
  library(zip)
  library(sf)
  library(here)
  
  
  #Create subdirectory
  outDir <- here::here(location, filename)
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
  zip::zip(zipfile = here::here(outDir, paste(filename, ".zip", sep="")),
           files = allShpNms,
           mode = "cherry-pick")
  
  
  #Remove raw files if desired
  if(zipOnly == TRUE) {
    file.copy(here(outDir, paste(filename, ".zip", sep="")), here::here(location, paste(filename, ".zip", sep="")))
    unlink(here(outDir), recursive = TRUE)          
  }
  
}

#Write as shapefile
st_write_shp(shp = nfpors %>% dplyr::mutate(PointId = objectid__) %>% dplyr::select(PointId),
             location = here::here("data", "raw"),
             filename = "West_NFPORS_2010_2021",
             zipOnly = FALSE)
