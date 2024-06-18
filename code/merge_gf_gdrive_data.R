# This script will read in a set of good fire data from your google drive and turn it into a single CSV


library('googledrive')
library('dplyr')
library('purrr')
library('here')


#################################################

# INPUTS ----

summarizeName <- 'sparkWatersheds'  # CHANGE THIS TO MATCH summarizeName IN GEE SCRIPT 2_full-streamlined-good-fire
driveFolder <- 'GEE_Exports'     # MAKE SURE THAT THIS IS THE GDRIVE FOLDER YOU ARE USING. 'GEE_Exports' is the default for the export script
years <- seq(2010,2020)       # This shouldn't need to be changed


##################################################


# FUNCTIONS ----

# A function to read a csv from a google drive path
read.csv.from.gdrive <- function(path) {
  f <- googledrive::drive_get(path)
  csv <- f |>
    googledrive::drive_read_string() %>%
    read.csv(text = .)
  return(csv)
}


# A function to read a good fire data file
read.gf.csv.from.gdrive <- function(year, summarizeName) {
  path <- paste0("~/", driveFolder, "/gf_data_", as.character(year), "_", summarizeName, ".csv")
  csv <- read.csv.from.gdrive(path = path)
  return(csv)
}


# OPERATE ----

# Map file over all years in the set and write as local csv
fullGFDataSet <- purrr::map(.x = years, .f = read.gf.csv.from.gdrive, summarizeName) |>
  dplyr::bind_rows()


readr::write_csv(fullGFDataSet, here::here('data', 'derived', paste0("gf_data_combined_", summarizeName, ".csv")))


# Clean dataset and re-write as clean dataset

cleanGFDataSet <- fullGFDataSet |>
  dplyr::select(-system.index, -.geo) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay')|>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
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

