# FCCS PSA Fuelbed Maps

Generate 30-meter Fuel Characteristic Classification System (FCCS) fuelbed maps and area summaries for Predictive Service Areas (PSAs) across the contiguous United States (CONUS), Alaska, Hawaii, and Puerto Rico.

The workflow uses LANDFIRE FCCS raster data to identify fuelbed classifications within each PSA, calculate their relative coverage, and produce standardized maps and CSV summaries.

## Requirements

The workflow requires R and the following packages:

- `sf`
- `terra`
- `dplyr`
- `readr`
- `kableExtra`
- `magick`

Install the required packages using:

```r
install.packages(c(
  "sf", "terra", "dplyr", "readr",
  "kableExtra", "magick"
))
```

## Directory structure

```text
fccs-psa-maps/
├── code/
│   └── fccs_psa_reports.R
├── data/
│   └── col_df.csv
├── gis/
├── output/
├── .gitignore
├── README.md
└── fccs-psa-maps.Rproj
```

The `gis/` and `output/` directories are excluded from Git.

## Input data

### 1. LANDFIRE FCCS rasters

Download the appropriate FCCS raster datasets from [LANDFIRE](https://www.landfire.gov/).

The workflow uses the following datasets:

| Region | Dataset |
|---|---|
| CONUS | LANDFIRE 2022 FCCS |
| Alaska | LANDFIRE 2022 FCCS |
| Hawaii | LANDFIRE 2022 FCCS |
| Puerto Rico | LANDFIRE 2023 FCCS |

The rasters have a spatial resolution of 30 meters.

The script currently expects these relative file paths:

```text
gis/
├── LF2022_FCCS_220_CONUS/
│   └── LF2022_FCCS_220_CONUS/
│       └── Tif/
│           └── LC22_FCCS_220.tif
├── LF2022_FCCS_220_AK/
│   └── LF2022_FCCS_220_AK/
│       └── Tif/
│           └── LA22_FCCS_220.tif
├── LF2022_FCCS_220_HI/
│   └── Tif/
│       └── LH22_FCCS_220.tif
└── LF2023_PRVI_240_IA/
    └── LF2023_FCCS_240_PRVI/
        └── Tif/
            └── LV23_FCCS_240.tif
```

These datasets are not included in the GitHub repository.

### 2. Predictive Service Area boundaries

Download the public Predictive Service Area (PSA) boundaries from the National Interagency Fire Center (NIFC) Open Data portal:

**[NIFC — Predictive Service Area (PSA) Boundaries (Public)](https://data-nifc.opendata.arcgis.com/datasets/nifc::predictive-service-area-psa-boundaries-public/about)**

Download the boundaries in GeoJSON format and place the file in the local `gis/` directory.

The current script expects the filename:

```text
gis/psa_boundaries.geojson
```

The GeoJSON is not included in this repository.

### 3. FCCS color lookup table

The repository includes:

```text
data/col_df.csv
```

This table contains the FCCS fuelbed classification codes and their associated map colors.

Disturbance-specific FCCS classifications are assigned the color of their parent FCCS fuelbed.

## Running the workflow

Open `fccs-psa-maps.Rproj` in RStudio, or set the working directory to the repository root.

Load the script:

```r
source("code/fccs_psa_reports.R")
```

### Generate an individual PSA map

For example, to generate a map for CONUS PSA 1:

```r
fccs_map_fun("1", "CONUS")
```

Supported region identifiers are:

- `"CONUS"` — Contiguous United States
- `"AK"` — Alaska
- `"HI"` — Hawaii
- `"PR"` — Puerto Rico

### Process an entire region

To generate maps and CSV summaries for all CONUS PSAs:

```r
conus_results <- run_psa_region("CONUS")
```

Review the processing results:

```r
table(conus_results$status)
```

Individual PSA failures are reported without stopping the entire batch.

PSAs outside the extent of their regional LANDFIRE raster are skipped.

## Outputs

Each successfully processed PSA generates two files in `output/`.

For example:

```text
output/
├── 1_30m_fccs_map.png
├── 1_30m_fccs_fuelbed_area.csv
├── 146_30m_fccs_map.png
└── 146_30m_fccs_fuelbed_area.csv
```

### FCCS map (PNG)

Each map displays the spatial distribution of FCCS fuelbed classifications within the PSA.

The accompanying legend identifies the 20 largest FCCS categories by area. Additional categories are summarized separately.

### Fuelbed area summary (CSV)

Each CSV contains:

| Column | Description |
|---|---|
| `base_fccs` | Parent FCCS fuelbed classification |
| `area_percentage` | Percentage of classified fuelbed area within the PSA |

Percentages are rounded to whole numbers. Categories rounding to less than 1% are displayed as `<1`.

## Processing notes

- LANDFIRE FCCS rasters are processed at their native 30-meter resolution.
- Raster categories representing disturbance-specific fuelbeds are grouped by their parent FCCS classification.
- FCCS category `0` (Bare Ground) is retained in the summaries.
- Fill, NoData, and Not Mapped categories are excluded from the area-percentage denominator.
- Areas are calculated from raster cell counts using the 30-meter cell area.
- Regional rasters use equal-area projections to support area calculations.
- The script processes PSAs individually to avoid loading all regional raster data into memory simultaneously.

## Data sources

- [LANDFIRE — Landscape Fire and Resource Management Planning Tools](https://www.landfire.gov/)
- [NIFC Open Data — Predictive Service Area Boundaries](https://data-nifc.opendata.arcgis.com/datasets/nifc::predictive-service-area-psa-boundaries-public/about)

LANDFIRE raster datasets and NIFC PSA boundaries remain the property of their respective data providers and are not redistributed through this repository.