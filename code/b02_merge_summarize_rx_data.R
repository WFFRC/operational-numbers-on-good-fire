
#This code section loads a personal utilities package (tlmr), and then uses it for package management
rm(list=ls()) #Ensure empty workspace if running from beginning
if (!requireNamespace("tlmr", quietly = TRUE)) {
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools")  # Install 'devtools' if it's not available
  }
  devtools::install_github('TylerLMcIntosh/tlm-r-utility', force = TRUE)
}
library(tlmr)
tlmr::install_and_load_packages(c("googledrive",
                                  "purrr",
                                  "here",
                                  "tidyverse",
                                  "sf"))


##################################################

# INPUTS ----

driveFolder <- 'GEE_Exports'
derivedDatDir <- here::here("data", "derived")
epsg <- 5070

##################################################

# FUNCTIONS ----

# A function to create the prescribed burning summary
# PARAMETERS
# polys :: the set of polygons to summarize by
# grpAttribute :: the name of the polygon attribute to use for summarizing, etc (should be a name of a column in the polygon set, as a character) e.g. "NAME"
create.rx.summary <- function(polys, grpAttribute) {
  allYrs <- seq(2010, 2020)
  uniquePolys <- unique(polys[[grpAttribute]])
  combos <- expand.grid(year = allYrs, grpAttribute = uniquePolys) |>
    setNames(c("year", as.character(substitute(grpAttribute))))
  
  rxSummary <- nfporsInterest |>
    sf::st_join(polys, join = sf::st_within) |>
    dplyr::group_by(!!rlang::sym(grpAttribute), ACTUALCOMPLETIONYEARNEW, FRGDescription) |>
    dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA),
                     nEvents = n()) |>
    dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
    dplyr::filter(!is.na({{grpAttribute}})) |>
    sf::st_drop_geometry() |>
    dplyr::mutate(rxBurnArea = rxBurnHa * 10000) |>
    mutate(units = "m^2") |>
    select(-rxBurnHa)
  
  rxSummary <- combos %>%
    dplyr::left_join(rxSummary, by = c('year', grpAttribute)) %>%
    replace(is.na(.), 0) |>
    dplyr::mutate(FRGDescription = ifelse(FRGDescription == 0, NA, FRGDescription))
  
  return(rxSummary)
}


# OPERATE ----

## Read in and merge rx datasets ----

# Read in RX data from GDrive & write local if not already acquired
localRxPath <- here::here(derivedDatDir, 'gee_nfpors_lcms_lcmap.csv')
if(!file.exists(localRxPath)) {
  rxGDrivePath <- paste0("~/", driveFolder, "gee_nfpors_lcms_lcmap.csv")
  geeNfporsDats <- tlmr::read_csv_from_gdrive(rxGDrivePath)
  write_csv(geeNfporsDats, localRxPath)
} else {
  geeNfporsDats <- readr::read_csv(here::here('data', 'derived', 'gee_nfpors_lcms_lcmap.csv'))
}


# Clean new data
geeNfporsDats <- geeNfporsDats |>
  dplyr::select(-`.geo`, -`system:index`)

# Load raw NFPORS RX data
nfpors <- sf::st_read(here::here('data', 'raw', 'NFPORS_WestStates_2010_2021', 'NFPORS_WestStates_2010_2021.gdb'),
                      layer = "West_NFPORS_2010_2021") |>
  dplyr::filter(!is.na(ACTUALCOMPLETIONDATE)) #ensure all included burns were actually done

#Manipulate raw NFPORS
unique(nfpors$TYPENAME)
unique(nfpors$actualcompletionyear)
unique(lubridate::year(as.Date(nfpors$ACTUALCOMPLETIONDATE)))
#actualcompletionyear has a few errors; make new one from the good data
nfpors <- nfpors %>%
  dplyr::mutate(ACTUALCOMPLETIONYEARNEW = lubridate::year(as.Date(ACTUALCOMPLETIONDATE)))


# Create contextual data for understanding GEE RX outputs

#LCMS classes; for context
lcmsClasses <- cbind(
  seq(1,15),
  c("Trees",
    "Tall Shrubs & Trees Mix (SEAK Only)",
    "Shrubs & Trees Mix",
    "Grass/Forb/Herb & Trees Mix",
    "Barren & Trees Mix",
    "Tall Shrubs (SEAK Only)",
    "Shrubs",
    "Grass/Forb/Herb & Shrubs Mix",
    "Barren & Shrubs Mix",
    "Grass/Forb/Herb",
    "Barren & Grass/Forb/Herb Mix",
    "Barren or Impervious",
    "Snow or Ice",
    "Water",
    "Non-Processing Area Mask")
) |>
  as.data.frame() |> 
  `names<-`(c("LCMS_LandCover_Code", "LCMS_LandCoverDescription")) |>
  dplyr::mutate(LCMS_LandCover_Code = as.double(LCMS_LandCover_Code))

#LCMS classes; for context
lcmapClasses <- cbind(
  seq(1,8),
  c("Developed",
    "Cropland",
    "Grass/shrubs",
    "Tree cover",
    "Water",
    "Wetland",
    "Ice and snow",
    "Barren")
) |>
  as.data.frame() |> 
  `names<-`(c("LCMAP_LandCover_Code", "LCMAP_LandCoverDescription")) |>
  dplyr::mutate(LCMAP_LandCover_Code = as.double(LCMAP_LandCover_Code))

#FRG classes; for context
frgClasses <- cbind(
  seq(1,3),
  c("frcLowMix",
    "frcReplace",
    "frcOther")) |>
  as.data.frame() |>
  `names<-`(c("FRG", "FRGDescription"))  |>
  dplyr::mutate(FRG = as.double(FRG))


#Join together and add column with land cover in burn year & landcover name, as well as FRG full name
nfporsWithGEE <- nfpors |>
  dplyr::mutate(PointId = objectid__) |>
  dplyr::left_join(geeNfporsDats, by = c("PointId")) |>
  dplyr::mutate(LCMSIndex = paste0("LandCover_LCMS_", (ACTUALCOMPLETIONYEARNEW - 1)),
                LCMAPIndex = paste0("LandCover_LCMAP_", (ACTUALCOMPLETIONYEARNEW - 1))) |> #THIS AND NEXT TWO LINES DO ROWWISE COMPUTE FOR THE LC_BURNYEAR
  dplyr::rowwise() |>
  dplyr::mutate(LCMS_PreBurnYear = get(LCMSIndex),
                LCMAP_PreBurnYear = get(LCMAPIndex)) |>
  dplyr::ungroup() |>
  as.data.frame() |>
  dplyr::left_join(lcmsClasses, by = c("LCMS_PreBurnYear" = "LCMS_LandCover_Code")) |> #join lcms landcover descriptions
  dplyr::left_join(lcmapClasses, by = c("LCMAP_PreBurnYear" = "LCMAP_LandCover_Code")) |>
  dplyr::left_join(frgClasses, by = c("frcRcls" = "FRG")) |> #join FRG descriptions
  dplyr::mutate(TOTALACCOMPLISHMENT_HA = TOTALACCOMPLISHMENT * 0.404686) #convert new HA column

#write out dataset
readr::write_csv(nfporsWithGEE, here::here(derivedDatDir, "nfpors_with_gee_lcms_lcmap.csv"))



# Summarize RX numbers ----

nfporsWithGee <- read_csv(here::here(derivedDatDir, "nfpors_with_gee_lcms_lcmap.csv"))
nfpors <- sf::st_read(here::here("data", "raw", "West_NFPORS_2010_2021", "West_NFPORS_2010_2021.shp")) |>
  sf::st_transform(epsg) 


#Join the NFPORS GEE data back to the original points & filter
nfporsInterest <- nfpors |>
  dplyr::left_join(nfporsWithGee, by = c("PointId" = "objectid__")) |>
  #dplyr::filter(FRGDescription == "frcLowMix"& ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(LCMS_PreBurnYear == 1 & LCMAP_PreBurnYear == 4)


sf::st_write(nfporsInterest, here::here(derivedDatDir, "nfpors_filtered_ready_for_analysis.gpkg"), append = FALSE)


# Prep summarizing polygons

# States
#Pull in state data as context
usa <- tigris::states() |>
  sf::st_transform(epsg)
west <- usa[usa$STUSPS %in% c("WA", "OR", "CA", "ID", "MT", "WY", "NV", "AZ", "CO", "NM", "UT"),]  

# Sparks
sparkWatersheds <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_watersheds.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(epsg) |>
  dplyr::mutate(sparkWatershed = name)

sparkWatershedsClean <- sparkWatersheds |>
  dplyr::select(sparkWatershed)


sparkCounties <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_counties.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(epsg) |>
  dplyr::mutate(sparkCounty = NAME)

sparkCountiesClean <- sparkCounties |>
  dplyr::select(sparkCounty)


sparkEcoregions <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_l4_ecoregions.shp')) |>
  sf::st_transform(epsg) |>
  dplyr::mutate(sparkEcoregion = US_L4CODE)

sparkEcoregionsJoin <- sparkEcoregions |>
  sf::st_drop_geometry() |>
  dplyr::select(-Shape_Leng, -Shape_Area) |>
  dplyr::distinct()

sparkEcoregionsClean <- sparkEcoregions |>
  dplyr::select(sparkEcoregion)



# Create RX summaries by summarizing polygons

#SPARKS
rxCountySummary <- create.rx.summary(polys = sparkCountiesClean, "sparkCounty") |>
  dplyr::left_join(sparkCounties, by = join_by(sparkCounty))
write_csv(rxCountySummary, here::here('data', 'derived', "rx_spark_county_summary.csv"))

rxWatershedSummary <- create.rx.summary(polys = sparkWatershedsClean, "sparkWatershed") |>
  dplyr::left_join(sparkWatersheds, by = join_by(sparkWatershed))
write_csv(rxWatershedSummary, here::here('data', 'derived', "rx_spark_watershed_summary.csv"))

rxEcoregionsSummary <- create.rx.summary(polys = sparkEcoregionsClean, "sparkEcoregion") |>
  dplyr::left_join(sparkEcoregionsJoin, by = join_by(sparkEcoregion))
write_csv(rxEcoregionsSummary, here::here('data', 'derived', "rx_spark_ecoregion_summary.csv"))


# STATES
rxStateSummary <- create.rx.summary(polys = west, "NAME")
write_csv(rxStateSummary, here::here('data', 'derived', "rx_state_summary.csv"))




