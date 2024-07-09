

library('googledrive')
library('tidyverse')
library('purrr')
library('here')
library('sf')



##################################################

# INPUTS ----

derivedDatDir <- here::here("data", "derived")
epsg <- 5070

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
    dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
    dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
    dplyr::filter(!is.na({{grpAttribute}})) |>
    sf::st_drop_geometry() |>
    dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)
  
  rxSummary <- combos %>%
    dplyr::left_join(rxSummary, by = c('year', grpAttribute)) %>%
    replace(is.na(.), 0) |>
    dplyr::mutate(FRGDescription = ifelse(FRGDescription == 0, NA, FRGDescription))
  
  return(rxSummary)
}

# OPERATE ----

nfporsWithGee <- read_csv(here::here(derivedDatDir, "nfpors_with_gee_lcms_lcmap.csv"))
nfpors <- sf::st_read(here::here("data", "raw", "West_NFPORS_2010_2021", "West_NFPORS_2010_2021.shp")) |>
  sf::st_transform(epsg) 


#Join the NFPORS GEE data back to the original points & filter
nfporsInterest <- nfpors |>
  dplyr::left_join(nfporsWithGee, by = c("PointId" = "objectid__")) |>
  #dplyr::filter(FRGDescription == "frcLowMix"& ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(LCMS_PreBurnYear == 1 & LCMAP_PreBurnYear == 4)

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

