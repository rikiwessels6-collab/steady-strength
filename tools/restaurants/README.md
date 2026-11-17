# Restaurant menu scrapers

One-off helpers used to build `Resources/Restaurants/restaurants.json` from each chain's own published figures.
They read files saved from the chain's site (not committed) and print what they leave out and why.

- `parse_dominos.py <saved dominos.com.au/nutrition html> <out.json>` then `build_dominos.py <that json> <items.json>`
- `parse_hj.py <folder of pdftotext -layout outputs of Hungry Jack's "Nutritionals" guides> <items.json>`

Nothing is estimated. Items whose published numbers contradict themselves are left out, or, where only the
energy total disagrees with the macros, kept as published with `publishedMismatch: true` and a note the app shows.
`tools/importer/test_restaurants.py` checks the result.
- `parse_subway.py <pdftotext -layout of Subway's AUS guide> <raw.json>` then `build_subway.py <raw.json> <items.json>`
- `parse_zambrero.py <pdftotext -layout of Zambrero's AUS guide> <items.json>` (logged by the serve: the guide gives no weights)
