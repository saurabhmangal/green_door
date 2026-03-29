# AGENTS.md

## Project Overview
This repository implements a frontend/backend audit application for evaluating PriceLabs nightly pricing recommendations against a comparable market dataset.

Primary purpose:
- Identify that whether the app `PriceLabs` is recommending right prices. 
- Highlight whether dates are underpriced, overpriced, or within market range
- Support inspection of listing comparables and PriceLabs input metadata
- The link of Pricelabs website is: https://hello.pricelabs.co/

Main users:
- developers maintaining the audit UI and comparison logic
- analysts validating PriceLabs output against sample and user-provided datasets

Tech stack:
- HTML/CSS/JavaScript frontend under `public/`
- local PowerShell launch scripts `server.ps1` and `Run-PriceLabsAudit.bat`
- JSON data-driven audit input under `data/`

---

## Repository Structure
- `README.md` → project overview, run instructions, dataset shape, and usage notes
- `data/` → sample dataset and any input JSON used by the app
- `cache/` → scraped PriceLabs public data; can be regenerated if needed
- `public/` → browser UI assets: `app.js`, `index.html`, `appendix.html`, `styles.css`
- `server.ps1`, `Run-PriceLabsAudit.bat` → local startup helpers

Follow the existing structure when adding new files or directories.

---

## Coding Guidelines
Follow these principles:
- Prefer readability over cleverness
- Keep JavaScript functions small and testable
- Reuse existing utilities before introducing new code paths
- Keep UI logic and data transformation logic separate when possible
- Preserve the app's local, static nature unless a strong reason exists to add tooling

Naming conventions:
- Files: lowercase with hyphens for new frontend assets
- Functions: `camelCase`
- Constants: `UPPER_SNAKE_CASE`
- DOM IDs/classes: kebab-case

When editing `public/app.js`, do not introduce large, untested behavior changes without validation in the browser.

---

## Change Rules for Agents
When making changes:
1. Do not modify unrelated files. Keep diffs small and focused.
2. Preserve the public interface of the audit dataset shape unless updating `README.md` and sample data.
3. Update `README.md` whenever the run flow, dataset shape, or expected behavior changes.
4. Avoid changing `server.ps1` or `Run-PriceLabsAudit.bat` unless requested.
5. Add comments for non-obvious logic, especially pricing or comparable scoring heuristics.

---

## Testing Requirements
Validate correctness by:
- running `powershell.exe -ExecutionPolicy Bypass -File .\server.ps1`
- opening `http://localhost:8787/`
- confirming the sample dataset loads and the audit UI renders
- verifying `public/index.html`, `public/app.js`, `public/styles.css`, and `public/appendix.html` still function

If you alter data ingestion or dataset shape:
- update `data/sample-dataset.json`
- update `README.md` dataset documentation
- confirm the UI still loads without script errors

---

## Safe Edit Zones
Agents MAY edit:
- `README.md` for docs updates
- `public/` assets for UI and audit logic changes
- `data/` sample datasets or dataset shape examples
- `cache/` only when updating scraping metadata or stored public PriceLabs data

Agents MUST NOT edit unless explicitly requested:
- `server.ps1`
- `Run-PriceLabsAudit.bat`
- `public/appendix.html` except when methodology or appendix content changes

---

## Dependency Policy
This repo is intentionally lightweight and local.
- Do not add new dependencies unless absolutely necessary.
- Prefer plain JavaScript, HTML, and CSS over build tooling.
- If a dependency is added, document why it is required and keep it minimal.

---

## Documentation Expectations
Agents should update:
- `README.md` when behavior changes or data requirements change
- `public/appendix.html` when the audit methodology changes
- inline comments in `public/app.js` when logic is complex

---

## Architecture Notes
Current flow:
1. Local `server.ps1` serves static files
2. `public/index.html` loads the audit UI
3. `public/app.js` reads sample or user-provided JSON data
4. The app compares `pricelabsRates` and `comparables` to score pricing

Do not bypass the intended frontend rendering path by adding hidden server-side behavior.

---

## Known Pitfalls
Do NOT:
- hardcode external URLs or live PriceLabs credentials
- change dataset semantics without updating documentation
- introduce unrelated backend/server complexity
- break the local run experience described in `README.md`

---

## Contact / Ownership
If you need clarification, follow the repository context and existing conventions. Keep changes conservative and document the reason for any structural or behavioral updates.
