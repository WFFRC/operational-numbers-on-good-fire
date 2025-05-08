# This script will read in a set of good fire data from your google drive and turn it into a single CSV

rm(list=ls()) #Ensure empty workspace if running from beginning

if(!requireNamespace("here", quietly = TRUE)) {
  install.packages("here")
}
library(here)

source(here::here("code", "functions.R"))

install_and_load_packages(c("googledrive",
                                  "dplyr",
                                  "purrr",
                                  "here"))

#################################################

# INPUTS ----

summarizeName <- 'states_no_reburn_v1'  # CHANGE THIS TO MATCH summarizeName IN GEE SCRIPT 2_full-streamlined-good-fire
driveFolder <- 'GEE_Exports'     # MAKE SURE THAT THIS IS THE GDRIVE FOLDER YOU ARE USING. 'GEE_Exports' is the default for the export script
earliestYear <- 2010
latestYear <- 2020


##################################################


# FUNCTIONS ----


# A function to read a good fire data file
read.gf.csv.from.gdrive <- function(year, summarizeName) {
  path <- paste0("~/", driveFolder, "/gf_data_", as.character(year), "_", summarizeName, ".csv")
  csv <- read_csv_from_gdrive(path = path)
  return(csv)
}


# OPERATE ----

# Manage GF summaries ----

years <- seq(earliestYear,latestYear)

# Map file over all years in the set and write as local csv
fullGFDataSet <- purrr::map(.x = years, .f = read.gf.csv.from.gdrive, summarizeName) |>
  dplyr::bind_rows() |>
  dplyr::select(-system.index, -.geo)


readr::write_csv(fullGFDataSet, here::here('data', 'derived', paste0("gf_data_combined_", summarizeName, "_", earliestYear, "_", latestYear, ".csv")))


## Clean dataset and re-write as clean dataset


if(grepl('spark', summarizeName)) {
  if(!summarizeName == 'sparkEcoregions') {
    cleanGFDataSet <- fullGFDataSet |>
      dplyr::filter(SPARK != 'AK - Bristol Bay') |>
      dplyr::filter(SPARK != 'BC - Bulkley Morice')
  }
}

cleanGFDataSet <- cleanGFDataSet |>
  dplyr::mutate(cbiAnyBurned = cbiAnyBurned * 0.000247105,
                cbiHigh = cbiHigh * 0.000247105,
                cbiLower = cbiLower * 0.000247105,
                cbiUnburned = cbiUnburned * 0.000247105,
                highGoodFire = highGoodFire * 0.000247105,
                lowerGoodFire = lowerGoodFire * 0.000247105,
                lowerRegimeCbiHigh = lowerRegimeCbiHigh * 0.000247105,
                lowerRegimeCbiUnburned = lowerRegimeCbiUnburned * 0.000247105,
                replaceRegimeCbiLow = replaceRegimeCbiLow * 0.000247105,
                replaceRegimeCbiUnburned = replaceRegimeCbiUnburned * 0.000247105,
                totalArea = totalArea * 0.000247105,
                yearPriorForest = yearPriorForest * 0.000247105) |>
  dplyr::rename(TotalBurnedForestAcres = cbiAnyBurned,
                TotalHighSeverityBurnedForestAcres = cbiHigh,
                TotalLowModSeverityBurnedForestAcres = cbiLower,
                TotalUnburnedForestWithinFirePerimetersAcres = cbiUnburned,
                HighSeverityGoodFireAcres = highGoodFire,
                LowerSeverityGoodFireAcres = lowerGoodFire,
                LowerRegimeHighSeverityBurnAcres = lowerRegimeCbiHigh,
                LowerRegimeUnburnedAcres = lowerRegimeCbiUnburned,
                ReplaceRegimeLowSeverityBurnAcres = replaceRegimeCbiLow,
                ReplaceRegimeUnburnedAcres = replaceRegimeCbiUnburned,
                TotalPolygonAreaAcres = totalArea,
                TotalForestedAreaInYearPriorAcres = yearPriorForest) |>
  dplyr::select(-units) |>
  dplyr::relocate(where(is.numeric), .after = where(is.character)) |>
  dplyr::relocate(TotalForestedAreaInYearPriorAcres, .before = TotalBurnedForestAcres) |>
  dplyr::relocate(TotalPolygonAreaAcres, .before = TotalForestedAreaInYearPriorAcres) |>
  dplyr::relocate(year, .before = TotalPolygonAreaAcres) |>
  dplyr::mutate(TotalGoodFireAcres = HighSeverityGoodFireAcres + LowerSeverityGoodFireAcres)

readr::write_csv(cleanGFDataSet, here::here('data', 'derived', paste0("clean_gf_data_combined_", summarizeName, ".csv")))



# Manage GF events ----

#GF event data from GDrive
gfEventDataFl <- here::here('data', 'derived', 'gf_fire_events_2010_2020.csv')
if(file.exists(gfEventDataFl)) {
  gfEventData <- readr::read_csv(gfEventDataFl)
} else {
  gfEventData <- read_csv_from_gdrive(paste0("~/", driveFolder, "/gf_data_fire_events_2010_2020.csv")) #from GEE
  readr::write_csv(gfEventData, gfEventDataFl)
}

# Raw GF events originally created
goodfireEventDatabase <- sf::st_read(here::here("data", "derived", "goodfire_dataset_for_analysis_2010_2020.gpkg")) |>
  sf::st_transform(sf::st_crs("EPSG:5070"))

# Join the data and export

allGFDats <- goodfireEventDatabase |>
  dplyr::left_join(gfEventData, by = "DatasetID")
sf::st_write(allGFDats, here::here("data", "derived", "merged_goodfire_final.gpkg"))

