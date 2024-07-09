

nfporsWithGee <- read_csv(here::here(derivedDatDir, "nfpors_with_gee_lcms_lcmap.csv"))
nfpors <- sf::st_read(here::here("data", "raw", "West_NFPORS_2010_2021", "West_NFPORS_2010_2021.shp")) |>
  sf::st_transform(5070) 


#Join the NFPORS GEE data back to the original points & filter
nfporsInterest <- nfpors |>
  dplyr::left_join(nfporsWithGee, by = c("PointId" = "objectid__")) |>
  dplyr::filter(FRGDescription == "frcLowMix"& ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(LCMS_PreBurnYear == 1 & LCMAP_PreBurnYear == 4)


# Manage spark data
sparkWatersheds <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_watersheds.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkWatershed = name)

sparkWatershedsClean <- sparkWatersheds |>
  dplyr::select(sparkWatershed)

  
sparkCounties <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_counties.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkCounty = NAME)

sparkCountiesClean <- sparkCounties |>
  dplyr::select(sparkCounty)


sparkEcoregions <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_l4_ecoregions.shp')) |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkEcoregion = US_L4CODE)

sparkEcoregionsClean <- sparkEcoregions |>
  dplyr::select(sparkEcoregion)



rxAllSparks <- nfporsInterest |>
  sf::st_join(sparkWatershedsClean, join = st_within) |>
  sf::st_join(sparkCountiesClean, join = st_within) |>
  sf::st_join(sparkEcoregionsClean, join = st_within)


rxCountySummary <- rxAllSparks |>
  dplyr::group_by(sparkCounty, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkCounty)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueCounties <- unique(sparkCounties$sparkCounty)
countyCombos <- expand.grid(year = allYrs, sparkCounty = uniqueCounties)

rxCountySummary <- countyCombos %>%
  left_join(rxCountySummary, by = c("year", "sparkCounty"))
rxCountySummary[is.na(rxCountySummary)] <- 0




rxEcoregionSummary <- rxAllSparks |>
  dplyr::group_by(sparkEcoregion, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkEcoregion)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueEcoregions <- unique(sparkEcoregions$sparkEcoregion)
ecoregionCombos <- expand.grid(year = allYrs, sparkEcoregion = uniqueEcoregions)

rxEcoregionSummary <- ecoregionCombos %>%
  left_join(rxEcoregionSummary, by = c("year", "sparkEcoregion"))
rxEcoregionSummary[is.na(rxEcoregionSummary)] <- 0




rxWatershedSummary <- rxAllSparks |>
  dplyr::group_by(sparkWatershed, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkWatershed)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueWatersheds <- unique(sparkWatersheds$sparkWatershed)
watershedCombos <- expand.grid(year = allYrs, sparkWatershed = uniqueWatersheds)

rxWatershedSummary <- watershedCombos %>%
  left_join(rxWatershedSummary, by = c("year", "sparkWatershed"))
rxWatershedSummary[is.na(rxWatershedSummary)] <- 0



rxWatershedSummaryFinal <- rxWatershedSummary |> left_join(sparkWatersheds, by = join_by(sparkWatershed))

sparkEcoregionsJoin <- sparkEcoregions |>
  sf::st_drop_geometry() |>
  dplyr::select(-Shape_Leng, -Shape_Area) |>
  dplyr::distinct()
  
rxEcoregionSummaryFinal <- rxEcoregionSummary |> left_join(sparkEcoregionsJoin, by = join_by(sparkEcoregion))
rxCountySummaryFinal <- rxCountySummary |> left_join(sparkCounties, by = join_by(sparkCounty))


write_csv(rxWatershedSummaryFinal, here::here('data', 'derived', "rx_spark_watershed_summary_lowmixonly.csv"))
write_csv(rxEcoregionSummaryFinal, here::here('data', 'derived', "rx_spark_ecoregion_summary_lowmixonly.csv"))
write_csv(rxCountySummaryFinal, here::here('data', 'derived', "rx_spark_county_summary_lowmixonly.csv"))










#Join the NFPORS GEE data back to the original points & filter
nfporsInterest <- nfpors |>
  dplyr::left_join(nfporsWithGee, by = c("PointId" = "objectid__")) |>
  dplyr::filter(ACTUALCOMPLETIONYEARNEW < 2021) |>
  dplyr::filter(LCMS_PreBurnYear == 1 & LCMAP_PreBurnYear == 4)


# Manage spark data
sparkWatersheds <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_watersheds.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkWatershed = name)

sparkWatershedsClean <- sparkWatersheds |>
  dplyr::select(sparkWatershed)


sparkCounties <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_counties.shp')) |>
  dplyr::filter(SPARK != 'AK - Bristol Bay') |>
  dplyr::filter(SPARK != 'BC - Bulkley Morice') |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkCounty = NAME)

sparkCountiesClean <- sparkCounties |>
  dplyr::select(sparkCounty)


sparkEcoregions <- sf::st_read(here::here('data', 'raw', 'SPARK-20240617T215254Z-001', 'SPARK', 'spark_l4_ecoregions.shp')) |>
  sf::st_transform(5070) |>
  dplyr::mutate(sparkEcoregion = US_L4CODE)

sparkEcoregionsClean <- sparkEcoregions |>
  dplyr::select(sparkEcoregion)



rxAllSparks <- nfporsInterest |>
  sf::st_join(sparkWatershedsClean, join = st_within) |>
  sf::st_join(sparkCountiesClean, join = st_within) |>
  sf::st_join(sparkEcoregionsClean, join = st_within)


rxCountySummary <- rxAllSparks |>
  dplyr::group_by(sparkCounty, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkCounty)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueCounties <- unique(sparkCounties$sparkCounty)
countyCombos <- expand.grid(year = allYrs, sparkCounty = uniqueCounties)

rxCountySummary <- countyCombos %>%
  left_join(rxCountySummary, by = c("year", "sparkCounty"))
rxCountySummary[is.na(rxCountySummary)] <- 0




rxEcoregionSummary <- rxAllSparks |>
  dplyr::group_by(sparkEcoregion, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkEcoregion)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueEcoregions <- unique(sparkEcoregions$sparkEcoregion)
ecoregionCombos <- expand.grid(year = allYrs, sparkEcoregion = uniqueEcoregions)

rxEcoregionSummary <- ecoregionCombos %>%
  left_join(rxEcoregionSummary, by = c("year", "sparkEcoregion"))
rxEcoregionSummary[is.na(rxEcoregionSummary)] <- 0




rxWatershedSummary <- rxAllSparks |>
  dplyr::group_by(sparkWatershed, ACTUALCOMPLETIONYEARNEW) |>
  dplyr::summarise(rxBurnHa = sum(TOTALACCOMPLISHMENT_HA)) |>
  dplyr::rename(year = ACTUALCOMPLETIONYEARNEW) |>
  dplyr::filter(!is.na(sparkWatershed)) |>
  sf::st_drop_geometry() |>
  dplyr::mutate(rxBurnAc = rxBurnHa * 2.47105)


allYrs <- seq(2010, 2020)
uniqueWatersheds <- unique(sparkWatersheds$sparkWatershed)
watershedCombos <- expand.grid(year = allYrs, sparkWatershed = uniqueWatersheds)

rxWatershedSummary <- watershedCombos %>%
  left_join(rxWatershedSummary, by = c("year", "sparkWatershed"))
rxWatershedSummary[is.na(rxWatershedSummary)] <- 0



rxWatershedSummaryFinal <- rxWatershedSummary |> left_join(sparkWatersheds, by = join_by(sparkWatershed))

sparkEcoregionsJoin <- sparkEcoregions |>
  sf::st_drop_geometry() |>
  dplyr::select(-Shape_Leng, -Shape_Area) |>
  dplyr::distinct()

rxEcoregionSummaryFinal <- rxEcoregionSummary |> left_join(sparkEcoregionsJoin, by = join_by(sparkEcoregion))
rxCountySummaryFinal <- rxCountySummary |> left_join(sparkCounties, by = join_by(sparkCounty))


write_csv(rxWatershedSummaryFinal, here::here('data', 'derived', "rx_spark_watershed_summary_anyRegime.csv"))
write_csv(rxEcoregionSummaryFinal, here::here('data', 'derived', "rx_spark_ecoregion_summary_anyRegime.csv"))
write_csv(rxCountySummaryFinal, here::here('data', 'derived', "rx_spark_county_summary_anyRegime.csv"))





rxWatershedSummaryFinalBoth <- rxWatershedSummaryFinal |>
  left_join(read_csv(here::here('data', 'derived', "rx_spark_watershed_summary_lowmixonly.csv")) |>
              dplyr::rename(rxBurnLowMixAc = rxBurnAc,
                            rxBurnLowMixHa = rxBurnHa) |>
              dplyr::select(-huc8, -geometry)) |>
  dplyr::rename(rxBurnAllAc = rxBurnAc,
                rxBurnAllHc = rxBurnHa) |>
  dplyr::select(-geometry)
write_csv(rxWatershedSummaryFinalBoth, here::here('data', 'derived', "rx_spark_watershed_summary_all.csv"))


rxEcoregionSummaryFinalBoth <- rxEcoregionSummaryFinal |>
  left_join(read_csv(here::here('data', 'derived', "rx_spark_ecoregion_summary_lowmixonly.csv")) |>
              dplyr::rename(rxBurnLowMixAc = rxBurnAc,
                            rxBurnLowMixHa = rxBurnHa) |>
              dplyr::select(rxBurnLowMixAc, rxBurnLowMixHa, year, sparkEcoregion)) |>
  dplyr::rename(rxBurnAllAc = rxBurnAc,
                rxBurnAllHc = rxBurnHa) |>
  sf::st_drop_geometry()
write_csv(rxEcoregionSummaryFinalBoth, here::here('data', 'derived', "rx_spark_ecoregion_summary_all.csv"))




rxCountySummaryFinalBoth <- rxCountySummaryFinal |>
  left_join(read_csv(here::here('data', 'derived', "rx_spark_county_summary_lowmixonly.csv")) |>
              dplyr::rename(rxBurnLowMixAc = rxBurnAc,
                            rxBurnLowMixHa = rxBurnHa) |>
              dplyr::select(rxBurnLowMixAc, rxBurnLowMixHa, year, sparkCounty)) |>
  dplyr::rename(rxBurnAllAc = rxBurnAc,
                rxBurnAllHc = rxBurnHa) |>
  sf::st_drop_geometry() |>
  dplyr::select(-geometry)
write_csv(rxCountySummaryFinalBoth, here::here('data', 'derived', "rx_spark_county_summary_all.csv"))


