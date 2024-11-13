source("renv/activate.R")


# .Rprofile in your project directory

# Check if 'renv' is installed; if not, offer to install it
if (!requireNamespace("renv", quietly = TRUE)) {
	message("renv is not installed; installing")
  install.packages("renv")
}

# Activate 'renv'
renv::activate()

# Ensure the 'renv/library/' directory exists if (!dir.exists("renv/library")) { dir.create("renv/library", recursive = TRUE) }

# Optionally restore the environment if the library is empty or missing
if (length(list.files("renv/library", recursive = TRUE, pattern = "DESCRIPTION")) <= 1) {
  response <- readline(prompt = "No packages detected in the renv library. Would you like to restore the environment? (y/n): ")
  if (tolower(response) == "y") {
    renv::restore(prompt = FALSE)
message("Environment restored. You may also consider running renv::rebuild() if you encounter compatibility issues.")
  } else {
    message("Skipping environment restore. Run renv::restore() to restore the environment if needed. You may also consider running renv::rebuild() if you encounter compatibility issues.")
  }
} else {
    message("Packages detected in the renv library. Skipping environment restoration.")
}


library(here)