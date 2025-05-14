#Zip WUMI unified perimeters together with metadata and html from script 04

##########################################################################
# USER SET PARAMETER
wumi_version <- "WUMI_20250509"
##########################################################################

if(!requireNamespace("here", quietly = TRUE)) {
  install.packages("here")
}
library(here)

source(here::here("code", "functions.R"))

install_and_load_packages(c("sf",
                            "here",
                            "httr",
                            "purrr",
                            "glue",
                            "tidyverse"))

dir_derived <- here::here("data", "derived")
dir_ensure(dir_derived)

rendered <- here::here('code', '04_fires_unify_wumi3.html')
dat <- here::here(dir_derived, paste0(wumi_version, "_main_fires_unified.gpkg"))

column_descriptions <- c(
  "Fire ID from WUMI 3)",
  "The dataset that the data came from",
  "The reporting agency",
  "The name of the fire, if available",
  "The date of the fire, if available",
  "Latitude",
  "Longitude",
  "Calculated area of the polygon",
  "Actual burned area within the polygon, if available",
  "Name in MTBS dataset",
  "ID in MTBS dataset",
  "Interagency IRWIN ID",
  "FOD ID",
  "FPA ID",
  "Interagency ID",
  "ID in Short database",
  "ID in NIFC database",
  "ID in Calfire database",
  "ID in GEOMAC database",
  "Human vs natural cause (if known)",
  "More specific cause (if known)",
  "The type of perimeter used in the prioritization scheme (added at unification step)",
  "The year of the fire if available (added at unification step)",
  "Geospatial delineation")

package_with_metadata(data_file_path = c(dat, rendered),
                      column_names = c("fireid", "dataset", "agency", "name", "date", "lat", "lon", "poly_area_ha", "burn_area_ha", "MTBS_name", "MTBS_ID", "IRWINID", "FOD_ID", "FPA_ID", "object_ID_interagency", "object_ID_short", "object_ID_nifc", "object_ID_calfire", "object_ID_geomac", "cause_human_or_natural", "cause_specific", "perimeter_type", "fire_year", "geometry"),
                      column_descriptions = column_descriptions,
                      overall_description = glue::glue("This is a unified perimeter set for the {wumi_version} dataset. The WUMI3 dataset is created by Park Williams, and is generated as a set of individual shapefiles. To streamline use by the WFFRC community, this dataset consists of a unified set of perimeters for the 'main fires' in the dataset. ('Main fires' meaning that some of the events are complex fires composed of multiple smaller events.) The WUMI3 dataset incorporates data from multiple different sources. The perimeters here have been selected using the following prioritization scheme:\n\n- MTBS whenever available CalFire if MTBS is not available\n- NIFC if neither of the above is available\n- GEOMAC if none of the above are available\n- Circle if none of the above area available\n\nFurther information on WUMI3, each data source included, and the unification process can be found in the rendered HTML file that is packaged with the data. All columns in the generated perimeter set are from the original WUMI3 data unless otherwise specified."),
                      author = "Tyler L. McIntosh",
                      github_repo = "https://github.com/WFFRC/operational-numbers-on-good-fire.git",
                      out_dir = dir_derived,
                      data_name_full = glue::glue("{wumi_version} unified main fire perimeters"),
                      data_name_file = glue::glue("{wumi_version}_main_fires_unified"),
                      compression_level = 9)

