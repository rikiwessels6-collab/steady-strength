# Australian nutrition catalogue

The new workflow and food diary use two independent sources.

- Supermarket lookup uses [Open Food Facts](https://openfoodfacts.github.io/openfoodfacts-server/api/). The optional ALDI, Woolworths, Coles and IGA filters require an Australian country tag and a matching store tag. These are community records, with no coverage or availability guarantee. The scheduled job takes the most recently modified results, up to 500 rows per retailer per run by default. It keeps Open Food Facts records under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) and in a separate database.
- The existing bundled restaurant menus and AUSNUT coffee ingredients still work. New restaurants, cafés and coffee products require approved Australian operator feeds. An empty feed configuration produces an empty operator snapshot. The collector never estimates missing nutrients, including fibre, and preserves source links and checked dates.

## Run and review

The GitHub Actions workflow runs tests on pull requests into the development base. Once the workflow is on the default branch, GitHub can run it on Mondays at 16:23 UTC (Tuesdays at 2:23 am Brisbane time), or manually. It writes reviewable JSON and SQLite snapshots as workflow artefacts with 30-day retention. It cannot publish app updates or change branches.

For approved feeds, set the GitHub Actions repository variable APPROVED_MENU_FEEDS to a JSON array of objects with an HTTPS url and a licence or documented permission reference. URLs should point to read-only, publicly reachable JSON. The workflow records the supplied permission reference. The maintainer must verify the right to reuse and distribute each feed before adding it.

The operator response is a JSON object with schemaVersion 1 and entries. Each entry includes country AU, category restaurant, cafe or coffee, checkedOn (YYYY-MM-DD), sourceURL and item. The item contains id, name, brand and per100 with kcal, protein, carbs and fat. Fibre, sugar and satFat are optional grams, and sodium is optional milligrams. Give servingGrams and optionally amountUnit mL for a per-100 mL drink. For food measured in grams, omit amountUnit. For an item published per serve with no weight, use a restaurant-serve-au-menu- prefixed ID, set servingGrams to 100, and include a servingLabel. Other operator IDs use au-menu-. Keep IDs stable across refreshes.

After reviewing a snapshot, approved app maintainers can host au-operator-menus.json at their chosen HTTPS endpoint and set the Xcode build setting NUTRITION_CATALOGUE_URL to that endpoint. The food diary refreshes a configured endpoint at most once a day after a successful fetch and uses the last validated download offline. The existing bundled content, food logs and saved items are independent of the downloaded menu.
