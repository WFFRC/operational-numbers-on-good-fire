# This script will create a set of polygons to use for the good fire project. It combines MTBS and combined wildland fire polygons
# This version of the code only uses the Welty & Jeffries polygons
# But excludes reburns through the entire history of the W&J dataset
# Tyler L. McIntosh 2025

rm(list = ls())

if(!requireNamespace("here", quietly = TRUE)) {
  install.packages("here")
}
library(here)

source(here::here("code", "functions.R"))

install_and_load_packages(c("tigris",
                            "tictoc",
                            "httr",
                            "jsonlite",
                            "sf",
                            "tidyverse"))

dir_derived <- here::here('data', 'derived')
dir_ensure(dir_derived)


# FUNCTIONS ----


get_non_overlapping_parts_fast <- function(polygons) {
  intersections <- st_intersects(polygons, polygons, sparse = TRUE)
  
  result <- map_dfr(seq_len(nrow(polygons)), function(i) {
    this_poly <- polygons[i, ]
    
    neighbors <- setdiff(intersections[[i]], i)
    
    if (length(neighbors) == 0) {
      return(this_poly)
    }
    
    other_union <- st_union(st_geometry(polygons[neighbors, ]))
    diff_geom <- st_difference(st_geometry(this_poly), other_union)
    
    if (length(diff_geom) == 0 || all(st_is_empty(diff_geom))) {
      return(NULL)
    } else {
      this_poly$geometry <- diff_geom
      return(this_poly)
    }
  })
  
  return(result)
}

get_non_overlapping_parts_fast_2 <- function(polygons1, polygons2) {
  # Precompute spatial index for efficiency
  intersection_index <- st_intersects(polygons1, polygons2, sparse = TRUE)
  
  result <- map_dfr(seq_len(nrow(polygons1)), function(i) {
    this_poly <- polygons1[i, ]
    neighbors_idx <- intersection_index[[i]]
    
    if (length(neighbors_idx) == 0) {
      return(this_poly)  # No overlap — return original
    }
    
    overlapping_union <- st_union(st_geometry(polygons2[neighbors_idx, ]))
    diff_geom <- st_difference(st_geometry(this_poly), overlapping_union)
    
    if (length(diff_geom) == 0 || all(st_is_empty(diff_geom))) {
      return(NULL)
    } else {
      this_poly$geometry <- diff_geom
      return(this_poly)
    }
  })
  
  return(result)
}


create_no_reburn_dataset <- function(dats, start_year, end_year, year_col) {
  subset <- dats |> 
    dplyr::filter({{year_col}} >= start_year & {{year_col}} <= end_year)
  
  pre_subset <- welty |>
    dplyr::filter({{year_col}}  < start_year)
  
  
  tic("Subset resolve overlap")
  subset_no_self_reburn <- subset |>
    get_non_overlapping_parts_fast()
  toc()
  tic("Non-subset resolve overlap")
  subset_no_reburn_all <- subset_no_self_reburn |>
    get_non_overlapping_parts_fast_2(polygons2 = pre_subset)
  toc()
  
  return(subset_no_reburn_all)
}



# Operate ----


epsg <- "EPSG:5070"

westernStates <- c("WA", "OR", "CA", "ID", "NV", "MT", "WY", "UT", "CO", "AZ", "NM")

west <- tigris::states() |>
  dplyr::filter(STUSPS %in% westernStates) |>
  sf::st_transform(epsg)

# The welty & jeffries combined fire polygon dataset can be acquired here: https://www.sciencebase.gov/catalog/item/61aa537dd34eb622f699df81
welty <- sf::st_read(here::here('data', 'raw', 'welty_combined_wildland_fire_dataset', 'welty_combined_wildland_fire_perimeters.shp')) |>
  sf::st_transform(epsg)

welty_wf <- welty|>
  dplyr::filter(Assigned_F == "Wildfire" | Assigned_F == "Likely Wildfire")


# Use functions
welty_no_reburn_2010_2020 <- create_no_reburn_dataset(
  dats = welty_wf,
  start_year = 2010,
  end_year = 2020,
  year_col = Fire_Year
)

welty_no_reburn_1984_2020 <- create_no_reburn_dataset(
  dats = welty_wf,
  start_year = 1984,
  end_year = 2020,
  year_col = Fire_Year
)



# Write files
flnm <- here::here(dir_derived, "goodfire_dataset_for_analysis_2010_2020_no_reburns.gpkg")
sf::st_write(welty_no_reburn_2010_2020, flnm, append = FALSE)
st_write_shp(shp = welty_no_reburn_2010_2020,
             location = dir_derived,
             filename = "goodfire_dataset_for_analysis_2010_2020_no_reburns",
             zip_only = TRUE,
             overwrite = TRUE)

flnm <- here::here(dir_derived, "goodfire_dataset_for_analysis_1984_2020_no_reburns.gpkg")
sf::st_write(welty_no_reburn_1984_2020, flnm, append = FALSE)
st_write_shp(shp = welty_no_reburn_1984_2020,
             location = dir_derived,
             filename = "goodfire_dataset_for_analysis_1984_2020_no_reburns",
             zip_only = TRUE,
             overwrite = TRUE)





# 
# # Testing ----
# 
# test_area <- mapedit::drawFeatures()
# test_area <- test_area |>
#   sf::st_transform(epsg)
# 
# 
# test_welty <- welty |>
#   st_filter(test_area) |>
#   dplyr::filter(Fire_Year > 2010)
# test_welty_early <- welty |>
#   st_filter(test_area) |>
#   dplyr::filter(Fire_Year <= 2010)
# 
# 
# y <- get_non_overlapping_parts_fast(test_welty_tiny_new)
# tic()
# z <- get_non_overlapping_parts_fast(test_welty)
# toc()
# mapview(test_welty) + mapview(z)
# 
# 
# xxx <- get_non_overlapping_parts_fast_2(polygons1 = z,
#                                         polygons2 = test_welty_early)
# 
# 
# mapview(test_welty_early) + mapview(test_welty) + mapview(z) + mapview(xxx)
# 


