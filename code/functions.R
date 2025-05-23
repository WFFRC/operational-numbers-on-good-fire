
#' Install and Load Required Packages Using pak
#'
#' This function checks if the specified packages (both CRAN and GitHub) are installed and loads them. 
#' If any packages are missing, it installs them automatically.
#' It uses the `pak` package for faster and more efficient package installation.
#'
#' @param package_list A list of package names to check and install (non-string, e.g., `c(dplyr, here)`).
#' GitHub packages should be specified as `username/repo` in strings.
#' @param auto_install A character ("y" or "n", default is "n"). If "y", installs all required packages 
#' without asking for user permission. If "n", asks for permission from the user.
#' @return No return value. Installs and loads the specified packages as needed.
#' @examples
#' \dontrun{
#' install_and_load_packages(c(dplyr, here, "username/repo"))
#' }
#' @importFrom pak pkg_install
#' @export
install_and_load_packages <- function(package_list, auto_install = "n") {
  # Convert non-string package names to strings
  package_list <- lapply(package_list, function(pkg) {
    if (is.symbol(pkg)) {
      deparse(substitute(pkg))
    } else {
      pkg
    }
  })
  
  # # Check if 'renv' is installed; if not, skip the 'renv' check
  # if (requireNamespace("renv", quietly = TRUE) && renv::is_active()) {
  #   cat("renv is active. Only loading packages...\n")
  #   for (pkg in package_list) {
  #     package_name <- if (grepl("/", pkg)) unlist(strsplit(pkg, "/"))[2] else pkg
  #     if (!require(package_name, character.only = TRUE)) {
  #       cat("Failed to load package:", package_name, "\n")
  #     }
  #   }
  #   return(invisible())
  # }
  
  # Check if pak is installed; install if not
  if (!requireNamespace("pak", quietly = TRUE)) {
    cat("The 'pak' package is required for fast installation of packages, installing now.\n")
    install.packages("pak")
  }
  
  # Initialize lists to store missing CRAN and GitHub packages
  missing_cran_packages <- c()
  missing_github_packages <- c()
  
  # # Helper function to get user input
  # get_user_permission <- function(prompt_msg) {
  #   if (auto_install == "y") {
  #     return("y")
  #   } else {
  #     return(tolower(readline(prompt = prompt_msg)))
  #   }
  # }
  
  # Check for missing packages
  for (pkg in package_list) {
    if (grepl("/", pkg)) { # GitHub package
      package_name <- unlist(strsplit(pkg, "/"))[2]
      package_loaded <- require(package_name, character.only = TRUE, quietly = TRUE)
    } else { # CRAN package
      package_loaded <- require(pkg, character.only = TRUE, quietly = TRUE)
    }
    if (!package_loaded) {
      if (grepl("/", pkg)) {
        missing_github_packages <- c(missing_github_packages, pkg)
      } else {
        missing_cran_packages <- c(missing_cran_packages, pkg)
      }
    }
  }
  
  # Install missing CRAN packages using pak::pkg_install
  if (length(missing_cran_packages) > 0) {
    # cat("The following CRAN packages are missing: ", paste(missing_cran_packages, collapse = ", "), "\n")
    # response <- get_user_permission("\nDo you want to install the missing CRAN packages? (y/n): ")
    # if (response == "y") {
      pak::pkg_install(missing_cran_packages, upgrade = TRUE)
    # } else {
    #   cat("Skipping installation of missing CRAN packages.\n")
    # }
  }
  
  # Install missing GitHub packages using pak::pkg_install
  if (length(missing_github_packages) > 0) {
    # cat("The following GitHub packages are missing: ", paste(missing_github_packages, collapse = ", "), "\n")
    # response <- get_user_permission("\nDo you want to install the missing GitHub packages? (y/n): ")
    # if (response == "y") {
      pak::pkg_install(missing_github_packages, upgrade = TRUE)
    # } else {
    #   cat("Skipping installation of missing GitHub packages.\n")
    # }
  }
  
  # Load all packages after checking for installation
  for (pkg in package_list) {
    if (grepl("/", pkg)) { # GitHub package
      package_name <- unlist(strsplit(pkg, "/"))[2]
      if (!require(package_name, character.only = TRUE)) {
        cat("Failed to load GitHub package:", package_name, "\n")
      }
    } else { # CRAN package
      if (!require(pkg, character.only = TRUE)) {
        cat("Failed to load CRAN package:", pkg, "\n")
      }
    }
  }
  
  cat("All specified packages installed and loaded.\n")
}




#' Read CSV from Google Drive Path
#'
#' This function reads a CSV file directly from a specified Google Drive path using the `googledrive` package. It first retrieves the file using the provided path and then reads the content into a data frame.
#'
#' @param path A character string specifying the Google Drive path to the CSV file. The path can be a file ID, URL, or a full path to the file.
#' @return A data frame containing the contents of the CSV file.
#' @details The function uses the `googledrive` package to access Google Drive files. Ensure that you have authenticated with Google Drive using `googledrive::drive_auth()` before using this function.
#' @examples
#' \dontrun{
#' # Example usage:
#' csv_data <- access_data_read_csv_from_gdrive("your-file-id-or-url")
#' head(csv_data)
#' }
#' @importFrom googledrive drive_get drive_read_string
#' @export
read_csv_from_gdrive <- function(path) {
  # Retrieve the file metadata from Google Drive
  f <- googledrive::drive_get(path)
  
  # Read the content of the file as a string and convert it to a data frame
  csv <- f |>
    googledrive::drive_read_string() %>%
    read.csv(text = .)
  
  return(csv)
}

#' Write Shapefile to a New Directory and Create a Zipped Version
#'
#' This function writes an `sf` object to a shapefile in a new, file-specific directory and optionally creates a zipped version of the shapefile.
#' It also allows for the removal of the original unzipped files and handles overwriting existing files.
#'
#' @param shp An `sf` object to write as a shapefile.
#' @param location A character string specifying the path of the directory to create the new file-specific subdirectory in.
#' @param filename A character string specifying the name of the file without the `.shp` extension.
#' @param zip_only A logical value indicating whether the original (unzipped) files should be removed after zipping. Defaults to `FALSE`.
#' @param overwrite A logical value indicating whether existing files should be overwritten. Defaults to `FALSE`.
#' @return No return value. The function writes a shapefile to a specified directory, optionally zips the files, and manages file cleanup based on user input.
#' @examples
#' \dontrun{
#' # Example usage
#' st_write_shp(shp = prepped_for_parks_etal,
#'              location = here::here("data/derived"),
#'              filename = "career_lba_for_parks_v1",
#'              zip_only = TRUE,
#'              overwrite = TRUE)
#' }
#' @importFrom sf st_write
#' @importFrom zip zip
#' @export
st_write_shp <- function(shp, location, filename, zip_only = FALSE, overwrite = FALSE) {
  
  # Define paths
  out_dir <- file.path(location, filename)
  zip_file <- file.path(out_dir, paste0(filename, ".zip"))
  zip_file_dest <- file.path(location, paste0(filename, ".zip"))
  
  # Manage overwriting and directory creation
  if (dir.exists(out_dir)) {
    if (overwrite) {
      unlink(out_dir, recursive = TRUE)
    } else {
      stop("Directory '", out_dir, "' already exists and overwrite is set to FALSE.")
    }
  }
  
  if (file.exists(zip_file_dest) && zip_only) {
    if (overwrite) {
      unlink(zip_file_dest)
    } else {
      stop("Zip file '", zip_file_dest, "' already exists and overwrite is set to FALSE.")
    }
  }
  
  # Create the directory if not there
  dir_ensure(out_dir)
  
  # Write the shapefile
  shapefile_path <- file.path(out_dir, paste0(filename, ".shp"))
  sf::st_write(shp, shapefile_path, append = FALSE)
  
  # Get all shapefile components
  all_shp_files <- list.files(out_dir, pattern = paste0(filename, ".*"), full.names = TRUE)
  
  # Create zip file
  zip::zip(zipfile = zip_file, files = all_shp_files, mode = "cherry-pick")
  
  # Remove raw files if zip_only is TRUE
  if (zip_only) {
    file.copy(zip_file, zip_file_dest)
    unlink(out_dir, recursive = TRUE)
  }
}


#' Safely Extract a ZIP or TAR Archive
#'
#' Handles both .zip and .tar(.gz) files. Supports skipping if files/folders exist,
#' recursive extraction of nested archives, and optional cleanup.
#'
#' @param archive_path Character. Path to a .zip, .tar, or .tar.gz file.
#' @param extract_to Character. Directory for extraction. Defaults to archive's directory.
#' @param recursive Logical. Recursively extract nested archives? Defaults to FALSE.
#' @param keep_archive Logical. Keep original and nested archives after extraction? Defaults to TRUE.
#' @param full_contents_check Logical. If TRUE, skip extraction only if all files exist.
#' @param return_all_paths Logical. If TRUE, return all extracted file paths;
#'                          if FALSE, return all top-level files and directories.
#'
#' @return Character vector of extracted paths.
#' @export
safe_extract <- function(archive_path,
                         extract_to = dirname(archive_path),
                         recursive = FALSE,
                         keep_archive = TRUE,
                         full_contents_check = FALSE,
                         return_all_paths = FALSE) {
  # --- Validate inputs ---
  if (!file.exists(archive_path)) stop("Archive does not exist: ", archive_path)
  if (!dir.exists(extract_to)) dir.create(extract_to, recursive = TRUE)
  
  ext <- tolower(tools::file_ext(archive_path))
  is_zip <- ext == "zip"
  is_tar <- ext %in% c("tar", "gz", "tgz", "tar.gz")
  
  if (!is_zip && !is_tar) stop("Unsupported archive type: ", ext)
  
  # --- List archive contents ---
  contents <- if (is_zip) {
    utils::unzip(archive_path, list = TRUE)$Name
  } else {
    utils::untar(archive_path, list = TRUE)
  }
  
  # Determine top-level items
  top_level_items <- unique(sub("^([^/]+).*", "\\1", contents))
  top_level_paths <- file.path(extract_to, top_level_items)
  
  # --- Skip logic ---
  skip_extract <- if (full_contents_check) {
    all(file.exists(file.path(extract_to, contents)))
  } else {
    all(file.exists(top_level_paths))
  }
  
  if (!skip_extract) {
    tryCatch({
      if (is_zip) {
        unzip(archive_path, exdir = extract_to)
      } else {
        utils::untar(archive_path, exdir = extract_to)
      }
    }, error = function(e) stop("Extraction failed: ", e$message))
    
    # --- Recursive extraction ---
    if (recursive) {
      nested_archives <- list.files(extract_to, pattern = "\\.(zip|tar|gz|tgz)$", recursive = TRUE, full.names = TRUE)
      nested_archives <- setdiff(nested_archives, archive_path)
      for (na in nested_archives) {
        safe_extract(na, dirname(na), recursive = recursive, keep_archive = keep_archive,
                     full_contents_check = FALSE, return_all_paths = FALSE)
        if (!keep_archive) unlink(na)
      }
    }
    
    if (!keep_archive) unlink(archive_path)
  } else {
    message("Skipping extract: Targets already exist in ", extract_to)
  }
  
  # --- Return paths ---
  if (return_all_paths) {
    # Get full paths of extracted files
    extracted_paths <- file.path(extract_to, contents)
    extracted_files <- extracted_paths[file.exists(extracted_paths) & !file.info(extracted_paths)$isdir]
    return(invisible(normalizePath(extracted_files, winslash = "/", mustWork = FALSE)))
  } else {
    paths <- file.path(extract_to, top_level_items)
    return(invisible(normalizePath(paths[file.exists(paths)], winslash = "/", mustWork = FALSE)))
  }
}


#' Safe Unzip a File (with Optional Recursive Unzipping and ZIP Cleanup)
#'
#' Safely unzips a ZIP file to a specified directory. Supports skipping extraction if files or top-level folder already exist, recursive unzipping of nested ZIPs, and optional deletion of ZIP files.
#'
#' @param zip_path Character. Path to the local ZIP file.
#' @param extract_to Character. Directory where the contents should be extracted. Defaults to the ZIP's directory.
#' @param recursive Logical. If TRUE, recursively unzip nested ZIP files. Defaults to FALSE.
#' @param keep_zip Logical. If FALSE, deletes the original ZIP and any nested ZIPs after unzipping. Defaults to TRUE.
#' @param full_contents_check Logical. If TRUE, skip unzip only if all expected files exist. If FALSE (default), skip unzip if the top-level directory exists.
#' @param return_all_paths Logical. If TRUE, returns full paths to all extracted files. If FALSE (default), returns only the top-level directory path.
#'
#' @return A character vector of extracted file paths (if \code{return_all_paths = TRUE}) or a single path to the top-level extracted directory (if \code{return_all_paths = FALSE}).
#'
#' @importFrom utils unzip
#' @export
#'
#' @examples
#' \dontrun{
#' # Recursively unzip and delete all ZIPs, return full paths
#' files <- safe_unzip("data/archive.zip", recursive = TRUE, keep_zip = FALSE, return_all_paths = TRUE)
#'
#' # Unzip only if top folder doesn't exist, return folder path
#' folder <- safe_unzip("data/archive.zip", full_contents_check = FALSE, return_all_paths = FALSE)
#' }
safe_unzip <- function(zip_path,
                       extract_to = dirname(zip_path),
                       recursive = FALSE,
                       keep_zip = TRUE,
                       full_contents_check = FALSE,
                       return_all_paths = FALSE) {
  # Validate inputs
  if (!file.exists(zip_path)) stop("ZIP file does not exist: ", zip_path)
  if (!is.character(extract_to) || length(extract_to) != 1) stop("`extract_to` must be a single character string.")
  if (!is.logical(recursive) || length(recursive) != 1) stop("`recursive` must be a single logical value.")
  if (!is.logical(keep_zip) || length(keep_zip) != 1) stop("`keep_zip` must be a single logical value.")
  if (!is.logical(full_contents_check) || length(full_contents_check) != 1) stop("`full_contents_check` must be logical.")
  if (!is.logical(return_all_paths) || length(return_all_paths) != 1) stop("`return_all_paths` must be logical.")
  
  # Get ZIP listing and top-level directory
  zip_listing <- unzip(zip_path, list = TRUE)
  top_level_dirs <- unique(sub("/.*", "", zip_listing$Name))
  top_dir_path <- file.path(extract_to, top_level_dirs[1])
  
  # Determine whether to skip unzip
  skip_unzip <- FALSE
  if (full_contents_check) {
    expected_paths <- file.path(extract_to, zip_listing$Name)
    skip_unzip <- all(file.exists(expected_paths))
  } else {
    skip_unzip <- dir.exists(top_dir_path)
  }
  
  if (!skip_unzip) {
    if (!dir.exists(extract_to)) dir.create(extract_to, recursive = TRUE)
    tryCatch({
      unzip(zip_path, exdir = extract_to)
    }, error = function(e) {
      stop("Failed to unzip: ", e$message)
    })
    
    if (recursive) {
      nested_zips <- list.files(extract_to, pattern = "\\.zip$", recursive = TRUE, full.names = TRUE)
      for (nz in nested_zips) {
        unzip(nz, exdir = dirname(nz))
        if (!keep_zip) unlink(nz)
      }
    }
    
    if (!keep_zip) unlink(zip_path)
  } else {
    message("Skipping unzip: Extraction target(s) already exist in ", extract_to)
  }
  
  if (return_all_paths) {
    all_files <- list.files(extract_to, recursive = TRUE, full.names = TRUE)
    file_paths <- all_files[file.info(all_files)$isdir == FALSE]
    return(invisible(normalizePath(file_paths, winslash = "/", mustWork = FALSE)))
  } else {
    return(invisible(normalizePath(top_dir_path, winslash = "/", mustWork = FALSE)))
  }
}


#' Safely Download a File to a Directory
#'
#' Downloads a file from a URL to a specified directory, only if it doesn't already exist there.
#'
#' @param url Character. The URL to download from.
#' @param dest_dir Character. The directory where the file should be saved.
#' @param mode Character. Mode passed to `download.file()`. Default is "wb" (write binary).
#' @param timeout Integer. Optional timeout in seconds. Will be reset afterward.
#'
#' @return A character string with the full path to the downloaded file.
#'
#' @importFrom utils download.file
#' @export
#'
#' @examples
#' \dontrun{
#' path <- safe_download("https://example.com/data.zip", "data/")
#' }
safe_download <- function(url,
                          dest_dir,
                          mode = "wb",
                          timeout = NA) {
  # Validate input
  if (!is.character(url) || length(url) != 1) stop("`url` must be a single character string.")
  if (!is.character(dest_dir) || length(dest_dir) != 1) stop("`dest_dir` must be a single character string.")
  
  # Ensure destination directory exists
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  
  # Derive destination file path from URL and directory
  filename <- basename(url)
  destfile <- file.path(dest_dir, filename)
  
  # Skip download if file already exists
  if (file.exists(destfile)) {
    message("Skipping download: File already exists at ", destfile)
    return(normalizePath(destfile, mustWork = FALSE))
  }
  
  # Handle optional timeout
  original_timeout <- getOption("timeout")
  if (!is.na(timeout) && timeout > original_timeout) {
    options(timeout = timeout)
    on.exit(options(timeout = original_timeout), add = TRUE)
  }
  
  # Attempt to download
  tryCatch({
    download.file(url, destfile, mode = mode)
    message("Downloaded: ", destfile)
  }, error = function(e) {
    stop("Failed to download file from URL: ", e$message)
  })
  
  return(normalizePath(destfile, mustWork = FALSE))
}


#' Ensure Directories Exist
#'
#' This function checks if one or more directories exist at the specified paths,
#' and creates any that do not exist.
#'
#' @param path A character string or a vector of strings specifying directory paths.
#' @return A character vector of all directory paths that were checked/created.
#' @examples
#' # Ensure a single directory
#' dir_ensure("data")
#'
#' # Ensure multiple directories
#' dir_ensure(c("data", "output", "logs"))
#'
#' @export
dir_ensure <- function(path) {
  if (!is.character(path)) {
    stop("`path` must be a character string or a vector of character strings.")
  }
  
  created_paths <- character()
  
  for (p in path) {
    if (!dir.exists(p)) {
      tryCatch({
        dir.create(p, recursive = TRUE)
        message("Directory created: ", p)
        created_paths <- c(created_paths, p)
      }, error = function(e) {
        warning("Failed to create directory: ", p, " — ", conditionMessage(e))
      })
    } else {
      message("Directory already exists: ", p)
    }
  }
  
  return(invisible(path))
}




#' Download a file from Google Drive to a local directory
#'
#' This function downloads a file from a Google Drive path to a specified local path.
#'
#' @param gDrivePath A character string. The path or name of the file on Google Drive.
#' @param localPath A character string. The local path where the file will be saved.
#' @param overwrite A logical value indicating whether to overwrite the file if it already exists at the local path. Defaults to `TRUE`.
#'
#' @details This function retrieves a file's ID from Google Drive using the provided `gDrivePath` and downloads it to the local directory specified by `localPath`. The file will be overwritten if `overwrite` is set to `TRUE` (default).
#' 
#' @return The downloaded file will be saved to the specified `localPath`.
#' 
#' @note You must be authenticated with Google Drive via the `googledrive` package for this function to work.
#' 
#' @importFrom googledrive drive_get drive_download as_id
#' 
#' @examples
#' \dontrun{
#' # Example usage:
#' download_data_from_gdrive("path/to/file/on/drive", "path/to/local/file.csv")
#' }
#' 
#' @export
download_data_from_gdrive <- function(gDrivePath, localPath) {
  # Validate inputs
  if (missing(gDrivePath) || missing(localPath)) {
    stop("Both 'gDrivePath' and 'localPath' must be provided.")
  }
  if (!is.character(gDrivePath) || !nzchar(gDrivePath)) {
    stop("'gDrivePath' must be a non-empty string.")
  }
  if (!is.character(localPath) || !nzchar(localPath)) {
    stop("'localPath' must be a non-empty string.")
  }
  
  # Retrieve file ID from GDrive
  f <- googledrive::drive_get(gDrivePath)
  id <- f$id
  nm <- f$name
  
  googledrive::drive_download(googledrive::as_id(id), path = localPath, overwrite = TRUE)
}

#' Package Existing Data File(s) with Metadata into ZIP
#'
#' Copies one or more existing data files, creates a Markdown metadata file using provided column names and descriptions, and packages all into a ZIP archive.
#'
#' @param data_file_path Character string or vector of file paths (e.g., CSVs).
#' @param column_names Character vector of column names.
#' @param column_descriptions Character vector of column descriptions (same length as column_names).
#' @param overall_description Overall dataset description.
#' @param author Author name.
#' @param github_repo GitHub repo URL.
#' @param out_dir Output directory path.
#' @param data_name_full Full dataset name for metadata.
#' @param data_name_file Base filename for output (no extension).
#' @param ... Additional parameters to pass to zip::zip
#'
#' @return NULL. Writes metadata and zip file to disk.
#'
#' @importFrom zip zip
package_with_metadata <- function(data_file_path, column_names, column_descriptions,
                                  overall_description, author, github_repo,
                                  out_dir, data_name_full, data_name_file, ...) {
  # Ensure data_file_path is a character vector
  if (!is.character(data_file_path)) {
    stop("data_file_path must be a character string or a character vector.")
  }
  
  # Check that all specified files exist
  missing_files <- data_file_path[!file.exists(data_file_path)]
  if (length(missing_files) > 0) {
    stop("The following files do not exist:\n", paste(missing_files, collapse = "\n"))
  }
  
  stopifnot(length(column_names) == length(column_descriptions))
  
  # Create metadata table
  df_metadata <- cbind(column_names, column_descriptions)
  
  # Create metadata markdown
  meta_path <- file.path(out_dir, "metadata.md")
  stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  
  sink(meta_path)
  cat("# Metadata for the ", data_name_full, " dataset\n")
  cat(overall_description, "\n\n")
  cat("## Information\n")
  cat("Author: ", author, "\n")
  cat("Date generated: ", stamp, "\n")
  cat("[GitHub repo with code for reproduction](", github_repo, ")\n\n")
  cat("## Metadata\n")
  cat("column_names :: column_descriptions\n")
  cat(apply(df_metadata, 1, paste, collapse = " :: "), sep = "\n")
  sink()
  
  # Zip files
  zip_path <- file.path(out_dir, paste0(data_name_file, ".zip"))
  zip::zip(zipfile = zip_path,
           files = c(data_file_path, meta_path),
           mode = "cherry-pick",
           ...)
  
  # Clean up temporary metadata file
  file.remove(meta_path)
}



## ArcGIS REST Data access

#' Robustly fetch data from ArcGIS REST API with pagination and partial result handling
#'
#' This version preserves partial data if an error occurs mid-fetch.
#'
#' @export
access_data_get_x_from_arcgis_rest_api_geojson <- function(base_url, query_params, max_record, n, timeout) {
  if (!is.character(base_url) || length(base_url) != 1) stop("Parameter 'base_url' must be a single character string.")
  if (!is.list(query_params)) stop("Parameter 'query_params' must be a list.")
  if (!is.numeric(max_record) || max_record <= 0) stop("Parameter 'max_record' must be a positive integer.")
  if (!is.numeric(timeout) || timeout <= 0) stop("Parameter 'timeout' must be a positive integer.")
  
  total_features <- list()
  offset <- 0
  total_fetched <- 0
  fetch_all <- identical(n, "all")
  
  if (!fetch_all && (!is.numeric(n) || n <= 0)) {
    stop("Parameter 'n' must be a positive integer or 'all'.")
  }
  
  repeat {
    query_params$resultOffset <- offset
    query_params$resultRecordCount <- max_record
    
    message(sprintf("Requesting records %d to %d...", offset + 1, offset + max_record))
    
    response <- tryCatch(
      httr::GET(url = base_url, query = query_params, httr::timeout(timeout)),
      error = function(e) {
        warning(sprintf("Request failed at offset %d: %s", offset, e$message))
        return(NULL)
      }
    )
    
    if (is.null(response)) break
    
    # Check content type
    resp_type <- httr::headers(response)[["content-type"]]
    if (!grepl("geo\\+json|application/json", resp_type)) {
      warning(sprintf("Non-GeoJSON response at offset %d. Skipping this batch.", offset))
      break
    }
    
    # Try to read the GeoJSON content
    data <- tryCatch({
      sf::st_read(httr::content(response, as = "text", encoding = "UTF-8"), quiet = TRUE)
    }, error = function(e) {
      warning(sprintf("Failed to parse GeoJSON at offset %d: %s", offset, e$message))
      return(NULL)
    })
    
    if (is.null(data) || nrow(data) == 0) {
      message("No more data returned.")
      break
    }
    
    total_features[[length(total_features) + 1]] <- data
    total_fetched <- total_fetched + nrow(data)
    message(sprintf("Fetched %d records so far...", total_fetched))
    
    if ((nrow(data) < max_record) || (!fetch_all && total_fetched >= n)) break
    
    offset <- offset + max_record
  }
  
  if (length(total_features) == 0) {
    warning("No data was successfully fetched.")
    return(NULL)
  }
  
  result <- do.call(rbind, total_features)
  
  if (!fetch_all) {
    result <- result[1:min(n, nrow(result)), ]
  }
  
  return(result)
}



merge_overlapping_matched_polygons <- function(sf_polygons, group_cols) {
  # Input checks
  if (!inherits(sf_polygons, "sf")) stop("Input must be an sf object.")
  if (!all(group_cols %in% names(sf_polygons))) stop("Some group_cols not found in the data.")
  
  # Detect geometry column
  geom_col <- attr(sf_polygons, "sf_column")
  if (is.null(geom_col)) {
    geom_candidates <- c("geometry", "geom", "shape")
    geom_col <- intersect(geom_candidates, names(sf_polygons))[1]
    if (is.na(geom_col)) stop("No geometry column found.")
    attr(sf_polygons, "sf_column") <- geom_col
    class(sf_polygons[[geom_col]]) <- c("sfc", class(sf_polygons[[geom_col]]))
  }
  
  # Make geometries valid
  x <- sf::st_make_valid(sf_polygons)
  
  # Initialize result container
  merged_list <- list()
  
  # Unique group combinations
  group_keys <- unique(x[, group_cols, drop = FALSE])
  
  for (i in seq_len(nrow(group_keys))) {
    # Build condition for filtering rows
    cond <- rep(TRUE, nrow(x))
    for (col in group_cols) {
      cond <- cond & x[[col]] == group_keys[[col]][i]
    }
    subset_x <- x[cond, ]
    if (nrow(subset_x) == 0) next
    
    # Build intersection graph
    adj <- sf::st_intersects(subset_x)
    comps <- igraph::components(igraph::graph.adjlist(adj))
    subset_x$group_id <- comps$membership
    
    # Split by component ID
    split_groups <- split(subset_x, subset_x$group_id)
    
    # Merge each component
    merged_parts <- lapply(split_groups, function(g) {
      # Take first row's attributes
      out <- g[1, , drop = FALSE]
      # Union geometry of all rows in group
      out[[geom_col]] <- sf::st_union(g[[geom_col]])
      return(out)
    })
    
    merged_list <- c(merged_list, merged_parts)
  }
  
  # Combine all results
  merged_result <- do.call(rbind, merged_list)
  merged_result$group_id <- NULL  # Drop temporary grouping column
  
  return(merged_result)
}

