# Export data to get lcms from GEE at nfpors points
# Tyler L. McIntosh
# CU Boulder CIRES Earth Lab


# SETUP ----

#This code section loads a personal utilities package (tlmr), and then uses it for package management
if (!requireNamespace("tlmr", quietly = TRUE)) {
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools")  # Install 'devtools' if it's not available
  }
  devtools::install_github('TylerLMcIntosh/tlm-r-utility', force = TRUE)
}
library(tlmr)
tlmr::install_and_load_packages(c("sf", "here", "dplyr"))


#Load data from geodatabase (provided by Karen Cummins, Tall Timbers)
# Data from National Fire Plan Operations and Reporting System (NFPORS)
nfpors <- sf::st_read(here::here('data', 'raw', 'NFPORS_WestStates_2010_2021', 'NFPORS_WestStates_2010_2021.gdb'),
                      layer = "West_NFPORS_2010_2021") |>
  dplyr::filter(!is.na(ACTUALCOMPLETIONDATE)) #ensure all included burns were actually done


#re-export as shp for GEE

#Write as shapefile
tlmr::st_write_shp(shp = nfpors |>
                     dplyr::mutate(PointId = objectid__) |>
                     dplyr::select(PointId),
             location = here::here("data", "raw"),
             filename = "West_NFPORS_2010_2021",
             zip_only = FALSE,
             overwrite = TRUE)
