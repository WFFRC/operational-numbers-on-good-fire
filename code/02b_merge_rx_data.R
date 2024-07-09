


library('googledrive')
library('tidyverse')
library('purrr')
library('here')



##################################################

# INPUTS ----

driveFolder <- 'GEE_Exports'
derivedDatDir <- here::here("data", "derived")


# FUNCTIONS ----

# A function to read a csv from a google drive path
read.csv.from.gdrive <- function(path) {
  f <- googledrive::drive_get(path)
  csv <- f |>
    googledrive::drive_read_string() %>%
    read.csv(text = .)
  return(csv)
}




# OPERATE ----

# Read in RX data from GDrive & write local if not already acquired
localRxPath <- here::here(derivedDatDir, 'gee_nfpors_lcms_lcmap.csv')
if(!file.exists(localRxPath)) {
  rxGDrivePath <- paste0("~/", driveFolder, "gee_nfpors_lcms_lcmap.csv")
  geeNfporsDats <- read.csv.from.gdrive(rxGDrivePath)
  write_csv(geeNfporsDats, localRxPath)
} else {
  geeNfporsDats <- readr::read_csv(here::here('data', 'derived', 'gee_nfpors_lcms_lcmap.csv'))
}


# Clean new data
geeNfporsDats <- geeNfporsDats |>
  dplyr::select(-`.geo`, -`system:index`)

# Load raw NFPORS RX data
nfpors <- sf::st_read(here::here('data', 'raw', 'NFPORS_WestStates_2010_2021', 'NFPORS_WestStates_2010_2021.gdb'),
                      layer = "West_NFPORS_2010_2021")|>
  dplyr::filter(!is.na(ACTUALCOMPLETIONDATE)) #ensure all included burns were actually done

#Manipulate raw NFPORS
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
write_csv(nfporsWithGEE, here::here(derivedDatDir, "nfpors_with_gee_lcms_lcmap.csv"))


