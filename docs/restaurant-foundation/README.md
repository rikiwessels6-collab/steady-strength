# Steady Strength — Australian Restaurant Nutrition Database (foundation)
Created: 17 November 2026

## What is actually included
- 56 Australian chain **catalogue candidates**, not verified menus or complete coverage.
- 9 historical starter nutrition rows preserved separately in `legacy_starter_items` and `menu_items.csv`. They are **NOT automatically cleared for production**; some are third-party/unverified or historical.
- `nutrition_items` contains **0 verified newly imported menu items**. It is intentionally empty to prevent false precision.
- CSV templates for independent establishments and official nutrition imports.
- SQLite indexes, source records, and country separation.

## IMPORTANT
This is NOT a complete Australian restaurant nutrition dataset. No national repository publishes full calories/macros for all Australian restaurants. Do not represent blank values as zero. Do not automatically treat estimates as official figures.

## Developer workflow
1. Import `establishment_catalogue.csv` into `establishments` (already populated in SQLite).
2. For each official chain nutrition publication, collect items and record country, serving, source URL, date, licence and verification.
3. Validate energy: kcal approximately kJ / 4.184, allowing rounding; do not derive missing macros from calories.
4. Use `nutrition_import_template.csv` column order to insert into `nutrition_items` after verifying source and reuse rights.
5. Store estimated meals separately with `data_quality=estimated`; never silently substitute for official brand data.
6. Display the source and checked date in the app. Refresh menus on a schedule and retire obsolete items.
7. Independently review licence terms for FSANZ, restaurants and third-party databases before commercial redistribution.

## Public sources and legal notes
- FSANZ AFCD (1,588 generic foods): https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd/data-files
- FSANZ AUSNUT 2023 (3,741 generic foods): https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/data-files
- FSANZ data licence: https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement
- Queensland menu kJ obligations: https://www.qld.gov.au/health/staying-healthy/food-pantry/food-labelling/kilojoule-menu-labelling

FSANZ data was NOT copied into this package: licensing and downstream distribution obligations require review. The original nine historical records retain their original source metadata.
