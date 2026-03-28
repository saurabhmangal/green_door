# PriceLabs Audit App

A small local frontend/backend app for testing whether `PriceLabs` recommendations look reasonable against a comparable market set.

## What it does

- Loads a built-in `Zalor Beach, South Goa` sample inspired by the shared ChatGPT conversation.
- Compares `PriceLabs` daily recommendations with a weighted market median.
- Scores comparable listings using bedroom count, guest capacity, pool match, walk distance, and rating.
- Highlights dates that look `underpriced`, `overpriced`, or `within market band`.
- Scrapes public `PriceLabs` pages so the UI can show what their website says about pricing inputs and controls.
- Lets you paste your own JSON dataset and rerun the audit without changing code.
- Generates Google search links for comparable listings, and uses a direct `listingUrl` when you include one in the dataset.

## Run it

From this folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\server.ps1
```

Then open:

```text
http://localhost:8787/
```

Methodology appendix:

```text
http://localhost:8787/appendix.html
```

There is also a helper launcher:

```text
Run-PriceLabsAudit.bat
```

## Dataset shape

The app expects one JSON document with:

- `meta`
- `subjectListing`
- `auditAssumptions`
- `pricelabsRates`
- `comparables`

See [`sample-dataset.json`](C:\Users\saura\Documents\green_door\data\sample-dataset.json) for the exact shape.

## Important note

The bundled Zalor sample is synthetic and only meant to demonstrate the workflow from the shared conversation. Replace it with real `PriceLabs` exports and real competitor calendar captures before using the output for pricing decisions.
