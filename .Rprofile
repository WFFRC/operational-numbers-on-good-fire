source("renv/activate.R")


# .Rprofile in your project directory

# Check if 'renv' is installed; if not, install it
if (!requireNamespace("renv", quietly = TRUE)) {
	message("renv is not installed; installing")
  install.packages("renv")
}

#Restore pak to use for faster package installation
renv::restore(packages = "pak", prompt = FALSE)

# Enable pak for faster installations with renv
options(renv.config.pak.enabled = TRUE)

# Activate 'renv'
renv::activate()

