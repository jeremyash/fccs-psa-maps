# LANDFIRE FCCS maps and fuelbed summaries for Predictive Service Areas
# Run from the project root. Requires the GIS rasters, PSA GeoJSON,
# and data/col_df.csv at the paths listed below.

library(sf)
library(terra)
library(dplyr)
library(readr)
library(kableExtra)
library(magick)

raster_paths <- c(
  CONUS = "gis/LF2022_FCCS_220_CONUS/LF2022_FCCS_220_CONUS/Tif/LC22_FCCS_220.tif",
  AK = "gis/LF2022_FCCS_220_AK/LF2022_FCCS_220_AK/Tif/LA22_FCCS_220.tif",
  HI = "gis/LF2022_FCCS_220_HI/Tif/LH22_FCCS_220.tif",
  PR = "gis/LF2023_PRVI_240_IA/LF2023_FCCS_240_PRVI/Tif/LV23_FCCS_240.tif"
)

psa_path <- paste0(
  "gis/DMP_Predictive_Service_Area__PSA_Boundaries_Public_",
  "4972049620355624354.geojson"
)

# A single PSA boundary dataset is shared by all regions.
psa_boundaries <- sf::st_read(psa_path, quiet = TRUE)

# Region assignment follows the supplied PSA data. Verify GACC assignments
# when updating the boundaries: the Northern California GACC label is being
# used for the five Hawaii PSAs in this particular dataset.
psa_regions <- psa_boundaries %>%
  sf::st_drop_geometry() %>%
  mutate(
    region = case_when(
      PSANAME == "PR" ~ "PR",
      GACCName == "Alaska Interagency Coordination Center" ~ "AK",
      GACCName == "Northern California Geographic Area Coordination Center" ~ "HI",
      TRUE ~ "CONUS"
    )
  ) %>%
  select(OBJECTID, region)

# Read once. Each base FCCS should have exactly one hex color.
colors <- readr::read_csv(
  "data/col_df.csv",
  col_types = readr::cols(base_fccs = readr::col_character(),
                           hex = readr::col_character())
) %>%
  mutate(base_fccs = as.character(as.numeric(base_fccs)))

if (anyDuplicated(colors$base_fccs)) {
  stop("Duplicate base FCCS codes in data/col_df.csv")
}

fccs_map_fun <- function(UNIT, REGION, AGENCY = "PSA") {
  UNIT <- as.character(UNIT)
  if (AGENCY != "PSA") stop("This shared version supports PSA boundaries only")
  if (!REGION %in% names(raster_paths)) stop("Unknown region: ", REGION)

  unit_unproj <- psa_boundaries %>%
    filter(as.character(OBJECTID) == UNIT)
  if (nrow(unit_unproj) == 0L) {
    message("Skipping PSA ", UNIT, ": boundary not found")
    return(invisible(NULL))
  }

  new_fac <- terra::rast(raster_paths[[REGION]])
  unit <- sf::st_transform(unit_unproj, crs = terra::crs(new_fac))

  # Skip PSAs outside raster extent (e.g., small Hawaii islands).
  if (!terra::relate(terra::ext(terra::vect(unit)),
                      terra::ext(new_fac), "intersects")) {
    message("Skipping PSA ", UNIT, ": outside ", REGION, " raster extent")
    return(invisible(NULL))
  }

  # Preserve original raster values, but derive the parent FCCS for each
  # disturbance-specific value (e.g., 0526-333 -> 526).
  base_fccs <- terra::cats(new_fac)[[1]] %>%
    select(Value, FCCS, FCCSID, R, G, B) %>%
    mutate(
      base_fccs = if_else(
        grepl("^Fill", FCCSID),
        as.character(FCCS),
        sub("[-_].*$", "", FCCSID)
      ),
      base_fccs = as.character(as.numeric(base_fccs))
    ) %>%
    arrange(Value)

  levels(new_fac) <- as.data.frame(base_fccs)
  activeCat(new_fac) <- 1

  map_colors <- base_fccs %>%
    select(Value, base_fccs) %>%
    left_join(colors, by = "base_fccs")

  # Fill categories may intentionally use their embedded colors.
  missing_colors <- map_colors %>%
    filter(is.na(hex), !Value %in% c(-9999, -1111))
  if (nrow(missing_colors) > 0L) {
    stop("Missing colors for parent FCCS: ",
         paste(unique(missing_colors$base_fccs), collapse = ", "))
  }

  # For the fill categories, use the original raster's embedded RGB values.
  map_colors <- map_colors %>%
    left_join(
      base_fccs %>%
        transmute(Value, original_hex = grDevices::rgb(R, G, B,
                                                       maxColorValue = 255)),
      by = "Value"
    ) %>%
    mutate(hex = coalesce(hex, original_hex)) %>%
    select(Value, hex)
  terra::coltab(new_fac) <- as.data.frame(map_colors)

  unit_new_cr <- terra::crop(new_fac, terra::vect(unit), snap = "out")
  unit_new <- terra::mask(unit_new_cr, terra::vect(unit))

  counts <- terra::freq(unit_new) %>%
    filter(!value %in% c(-9999, -1111))
  if (nrow(counts) == 0L) {
    message("Skipping PSA ", UNIT, ": no classified FCCS cells")
    return(invisible(NULL))
  }

  # The four source rasters have been verified as 30 m equal-area rasters.
  area_df <- counts %>%
    left_join(base_fccs %>% select(Value, base_fccs),
              by = c("value" = "Value"))
  if (anyNA(area_df$base_fccs)) {
    stop("Unmatched raster category in PSA ", UNIT)
  }
  area_df <- area_df %>%
    group_by(base_fccs) %>%
    summarise(cell_count = sum(count), .groups = "drop") %>%
    mutate(
      area_acres = cell_count * prod(terra::res(new_fac)) * 0.000247105,
      area_pct = 100 * area_acres / sum(area_acres),
      area_percentage = if_else(
        round(area_pct) < 1,
        "<1",
        as.character(round(area_pct))
      ),
      base_fccs_num = as.numeric(base_fccs)
    ) %>%
    arrange(desc(area_pct), base_fccs_num)

  out_dir <- "output"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  prefix <- file.path(out_dir, paste0(UNIT, "_30m_fccs"))

  readr::write_csv(
    area_df %>% transmute(base_fccs = base_fccs_num, area_percentage),
    paste0(prefix, "_fuelbed_area.csv")
  )

  legend_df <- area_df %>%
    left_join(colors, by = "base_fccs") %>%
    mutate(blank = "")
  if (anyNA(legend_df$hex)) stop("Legend colors missing for PSA ", UNIT)

  n_legend <- min(20L, nrow(legend_df))
  shown <- legend_df[seq_len(n_legend), ]
  other <- if (nrow(legend_df) > n_legend) {
    legend_df$base_fccs_num[seq.int(n_legend + 1L, nrow(legend_df))]
  } else {
    numeric(0)
  }
  other <- sort(other)
  other_text <- if (length(other) == 0L) {
    ""
  } else if (length(other) == 1L) {
    paste0("Other fuelbeds include: ", other, ".")
  } else {
    paste0("Other fuelbeds include: ",
           paste(head(other, -1L), collapse = ", "),
           " and ", tail(other, 1L), ".")
  }

  legend_table <- kableExtra::kbl(
    shown %>% select(blank, base_fccs_num, area_percentage),
    booktabs = TRUE,
    linesep = "",
    col.names = kableExtra::linebreak(c(" ", "FCCS", "Area (%)")),
    align = "c", format = "html"
  ) %>%
    kableExtra::kable_styling(full_width = FALSE) %>%
    kableExtra::kable_styling(font_size = 10, position = "center") %>%
    kableExtra::column_spec(1, color = "black", background = shown$hex,
                            width = "0.5in") %>%
    kableExtra::column_spec(2, width = "0.5in") %>%
    kableExtra::column_spec(3, width = "0.5in") %>%
    kableExtra::footnote(general = other_text, general_title = "",
                         threeparttable = TRUE)

  map_file <- tempfile(fileext = ".png")
  legend_file <- tempfile(fileext = ".png")
  on.exit(unlink(c(map_file, legend_file)), add = TRUE)

  grDevices::png(map_file, height = 1000, width = 1000)
  tryCatch({
    terra::plot(unit_new, legend = FALSE, axes = FALSE, box = FALSE,
                maxcell = 5e8, oma = c(5, 5, 5, 5), mar = c(2, 2, 2, 2))
    plot(sf::st_geometry(unit), add = TRUE)
  }, finally = grDevices::dev.off())

  kableExtra::save_kable(legend_table, file = legend_file,
                          density = 1000, zoom = 1.3)
  magick::image_write(
    magick::image_append(c(magick::image_read(map_file),
                           magick::image_read(legend_file))),
    paste0(prefix, "_map.png")
  )
  invisible(paste0(prefix, "_map.png"))
}

# Batch runner: logs success, skips and errors; keeps going after an error.
run_psa_region <- function(region, ids = psa_regions$OBJECTID[psa_regions$region == region]) {
  results <- lapply(as.character(ids), function(id) {
    tryCatch({
      output <- fccs_map_fun(id, region, "PSA")
      data.frame(region = region, psa = id,
                 status = if (is.null(output)) "skipped" else "success",
                 detail = if (is.null(output)) "no output" else output)
    }, error = function(e) {
      message("ERROR PSA ", id, " (", region, "): ", conditionMessage(e))
      data.frame(region = region, psa = id, status = "error",
                 detail = conditionMessage(e))
    })
  })
  dplyr::bind_rows(results)
}

# Start with one PSA per region to verify the shared script:
# fccs_map_fun("1", "CONUS")
# fccs_map_fun("15", "AK")
# fccs_map_fun("107", "HI")
# fccs_map_fun("146", "PR")

# When ready, run the regional batches separately:
# conus_results <- run_psa_region("CONUS")
# ak_results    <- run_psa_region("AK")
# hi_results    <- run_psa_region("HI")
# pr_results    <- run_psa_region("PR")
# dplyr::count(conus_results, status)
