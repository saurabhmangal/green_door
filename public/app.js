const state = {
  dataset: null,
  sampleDataset: null,
  analysis: null,
  publicIntel: null,
};

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (value == null) return [];
  return [value];
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeUrl(value) {
  if (typeof value !== "string" || !value.trim()) return "";
  try {
    const url = new URL(value);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return url.toString();
    }
  } catch (_) {
    return "";
  }
  return "";
}

function buildGoogleSearchUrl(parts) {
  const query = parts.filter(Boolean).join(" ").trim();
  if (!query) return "";
  return `https://www.google.com/search?q=${encodeURIComponent(query)}`;
}

const els = {
  statusTitle: document.getElementById("status-title"),
  statusHeadline: document.getElementById("status-headline"),
  summaryGrid: document.getElementById("summary-grid"),
  chartHost: document.getElementById("chart-host"),
  insightsList: document.getElementById("insights-list"),
  comparablesBody: document.getElementById("comparables-body"),
  dailyBody: document.getElementById("daily-body"),
  sourcesList: document.getElementById("sources-list"),
  datasetEditor: document.getElementById("dataset-editor"),
  subjectCard: document.getElementById("subject-card"),
  template: document.getElementById("metric-card-template"),
  horizonDays: document.getElementById("horizonDays"),
  horizonDaysValue: document.getElementById("horizonDaysValue"),
  minimumRating: document.getElementById("minimumRating"),
  minimumRatingValue: document.getElementById("minimumRatingValue"),
  maxWalkMinutes: document.getElementById("maxWalkMinutes"),
  maxWalkMinutesValue: document.getElementById("maxWalkMinutesValue"),
  minSimilarity: document.getElementById("minSimilarity"),
  minSimilarityValue: document.getElementById("minSimilarityValue"),
  strictPoolMatch: document.getElementById("strictPoolMatch"),
  refreshSources: document.getElementById("refresh-sources"),
  runAnalysis: document.getElementById("run-analysis"),
  applyDataset: document.getElementById("apply-dataset"),
  loadSample: document.getElementById("load-sample"),
  scrapeListing: document.getElementById("scrape-listing"),
};

function formatCurrency(value) {
  if (value == null) return "NA";
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: state.dataset?.meta?.currency || "INR",
    maximumFractionDigits: 0,
  }).format(value);
}

function formatPercent(value) {
  if (value == null) return "NA";
  return `${value.toFixed(1)}%`;
}

function statusClass(action) {
  if (action === "Raise") return "status-raise";
  if (action === "Lower") return "status-lower";
  if (action === "Hold") return "status-hold";
  return "status-neutral";
}

function getCurrentOptions() {
  return {
    horizonDays: Number(els.horizonDays.value),
    minimumRating: Number(els.minimumRating.value),
    maxWalkMinutes: Number(els.maxWalkMinutes.value),
    minSimilarity: Number(els.minSimilarity.value),
    strictPoolMatch: els.strictPoolMatch.checked,
  };
}

function syncControlLabels() {
  els.horizonDaysValue.textContent = `${els.horizonDays.value} nights`;
  els.minimumRatingValue.textContent = Number(els.minimumRating.value).toFixed(2);
  els.maxWalkMinutesValue.textContent = `${els.maxWalkMinutes.value} min`;
  els.minSimilarityValue.textContent = `${Math.round(Number(els.minSimilarity.value) * 100)}%`;
}

function applyOptionsToControls(options) {
  els.horizonDays.value = options.horizonDays;
  els.minimumRating.value = options.minimumRating;
  els.maxWalkMinutes.value = options.maxWalkMinutes;
  els.minSimilarity.value = options.minSimilarity;
  els.strictPoolMatch.checked = Boolean(options.strictPoolMatch);
  syncControlLabels();
}

function renderSubject() {
  const subject = state.dataset.subjectListing;
  const notes = (subject.notes || []).map((note) => `<li>${note}</li>`).join("");
  const subjectLink = normalizeUrl(subject.listingUrl || subject.sourceUrl || subject.url || "");
  const linkMarkup = subjectLink
    ? `<p><a class="text-link" href="${subjectLink}" target="_blank" rel="noreferrer">Open subject Airbnb listing</a></p>`
    : "";

  els.subjectCard.innerHTML = `
    <p class="eyebrow">Current Subject</p>
    <h3>${subject.name}</h3>
    <p>${subject.bedrooms}BR &middot; sleeps ${subject.maxGuests} &middot; ${subject.hasPool ? "pool" : "no pool"} &middot; ${subject.walkMinutesToBeach} min walk</p>
    <p>${state.dataset.meta.microMarket}</p>
    ${linkMarkup}
    <ul class="insights-list">${notes}</ul>
  `;
}

function makeMetric(label, value, footnote) {
  const fragment = els.template.content.cloneNode(true);
  fragment.querySelector(".metric-label").textContent = label;
  fragment.querySelector(".metric-value").textContent = value;
  fragment.querySelector(".metric-footnote").textContent = footnote;
  return fragment;
}

function renderSummary() {
  const summary = state.analysis.summary;
  els.summaryGrid.innerHTML = "";
  els.summaryGrid.appendChild(makeMetric(
    "Median gap",
    summary.medianGapPercent == null ? "NA" : formatPercent(summary.medianGapPercent),
    summary.medianGapPercent >= 0 ? "Positive means market is above PriceLabs." : "Negative means PriceLabs is above the market."
  ));
  els.summaryGrid.appendChild(makeMetric(
    "Price index",
    summary.priceIndex == null ? "NA" : summary.priceIndex.toFixed(2),
    "PriceLabs divided by weighted market median."
  ));
  els.summaryGrid.appendChild(makeMetric(
    "Revenue uplift",
    formatCurrency(summary.opportunityUplift),
    "Potential upside if you raise underpriced dates toward market median."
  ));
  els.summaryGrid.appendChild(makeMetric(
    "Confidence",
    formatPercent(summary.averageConfidence),
    `${summary.underpricedDays} underpriced days and ${summary.overpricedDays} overpriced days in the active window.`
  ));
}

function renderStatus() {
  els.statusTitle.textContent = state.analysis.status;
  els.statusHeadline.textContent = state.analysis.headline;
}

function renderInsights() {
  els.insightsList.innerHTML = asArray(state.analysis.insights).map((item) => `<li>${item}</li>`).join("");
}

function getComparableRecord(compId) {
  return asArray(state.dataset?.comparables).find((comp) => comp.id === compId) || null;
}

function getComparableLinks(comp) {
  const record = getComparableRecord(comp.id);
  const directUrl = normalizeUrl(record?.listingUrl || record?.sourceUrl || record?.url || "");
  const microMarket = state.dataset?.meta?.microMarket || state.dataset?.subjectListing?.market || "";
  const googleSearchUrl = buildGoogleSearchUrl([comp.name, comp.source, microMarket]);
  return { directUrl, googleSearchUrl };
}

function renderComparables() {
  els.comparablesBody.innerHTML = asArray(state.analysis.comparableSummary).map((comp) => {
    const links = getComparableLinks(comp);
    const linkItems = [];
    if (links.directUrl) {
      linkItems.push(`<a class="text-link" href="${links.directUrl}" target="_blank" rel="noreferrer">Open listing</a>`);
    }
    if (links.googleSearchUrl) {
      linkItems.push(`<a class="text-link" href="${links.googleSearchUrl}" target="_blank" rel="noreferrer">Google search</a>`);
    }

    return `
      <tr>
        <td>
          <strong>${comp.name}</strong><br>
          <span class="subtle">${comp.source} &middot; ${comp.bedrooms}BR &middot; sleeps ${comp.maxGuests}</span>
          <div class="inline-links">${linkItems.join('<span class="link-divider">|</span>')}</div>
        </td>
        <td>${comp.similarity.toFixed(1)}%</td>
        <td>${formatCurrency(comp.medianAdr)}</td>
        <td>${formatPercent(comp.occupancyProxy)}</td>
        <td>${comp.walkMinutesToBeach} min</td>
      </tr>
    `;
  }).join("");
}

function renderDailyTable() {
  els.dailyBody.innerHTML = asArray(state.analysis.dailyComparison).map((row) => {
    const gapClass = row.gapAmount > 0 ? "positive" : row.gapAmount < 0 ? "negative" : "subtle";
    return `
      <tr>
        <td>${row.date}</td>
        <td>${formatCurrency(row.priceLabs)}</td>
        <td>${formatCurrency(row.marketMedian)}</td>
        <td>${formatCurrency(row.marketLow)} to ${formatCurrency(row.marketHigh)}</td>
        <td class="${gapClass}">
          ${row.gapAmount == null ? "NA" : `${formatCurrency(row.gapAmount)} (${formatPercent(row.gapPercent)})`}
        </td>
        <td><span class="status-pill ${statusClass(row.action)}">${row.action}</span></td>
        <td>${formatPercent(row.confidence)}</td>
      </tr>
    `;
  }).join("");
}

function renderSources() {
  const warnings = asArray(state.publicIntel?.warnings);
  const warningMarkup = warnings.length
    ? `<div class="source-card"><h3>Scrape warnings</h3><p>${warnings.join("<br>")}</p></div>`
    : "";
  const sourceMarkup = asArray(state.publicIntel?.sources).map((source) => `
    <article class="source-card">
      <h3><a href="${source.url}" target="_blank" rel="noreferrer">${source.title}</a></h3>
      <p>${source.snippet}</p>
    </article>
  `).join("");
  els.sourcesList.innerHTML = warningMarkup + sourceMarkup;
}

function renderChart() {
  const rows = asArray(state.analysis.dailyComparison).filter((row) => row.marketMedian != null);
  if (!rows.length) {
    els.chartHost.innerHTML = "<p>No chart data available.</p>";
    return;
  }

  const width = 980;
  const height = 320;
  const pad = { top: 24, right: 24, bottom: 52, left: 68 };
  const plotWidth = width - pad.left - pad.right;
  const plotHeight = height - pad.top - pad.bottom;

  const allValues = rows.flatMap((row) => [row.priceLabs, row.marketMedian, row.marketLow, row.marketHigh]).filter(Boolean);
  const minValue = Math.min(...allValues);
  const maxValue = Math.max(...allValues);
  const range = Math.max(1, maxValue - minValue);

  const xForIndex = (index) => pad.left + (plotWidth * index) / Math.max(rows.length - 1, 1);
  const yForValue = (value) => pad.top + plotHeight - (((value - minValue) / range) * plotHeight);

  const bandTop = rows.map((row, index) => `${xForIndex(index)},${yForValue(row.marketHigh)}`).join(" ");
  const bandBottom = [...rows].reverse().map((row, index) => {
    const trueIndex = rows.length - 1 - index;
    return `${xForIndex(trueIndex)},${yForValue(row.marketLow)}`;
  }).join(" ");

  const marketLine = rows.map((row, index) => `${xForIndex(index)},${yForValue(row.marketMedian)}`).join(" ");
  const priceLabsLine = rows.map((row, index) => `${xForIndex(index)},${yForValue(row.priceLabs)}`).join(" ");

  const yTicks = Array.from({ length: 5 }, (_, idx) => {
    const ratio = idx / 4;
    return {
      value: maxValue - ratio * range,
      y: pad.top + plotHeight * ratio,
    };
  });

  const xLabels = rows.map((row, index) => {
    const show = index === 0 || index === rows.length - 1 || index % 3 === 0;
    if (!show) return "";
    return `<text x="${xForIndex(index)}" y="${height - 18}" text-anchor="middle">${row.date.slice(5)}</text>`;
  }).join("");

  const yLabels = yTicks.map((tick) => `
    <g>
      <line x1="${pad.left}" y1="${tick.y}" x2="${width - pad.right}" y2="${tick.y}" stroke="rgba(19,42,40,0.09)" stroke-dasharray="4 6" />
      <text x="${pad.left - 10}" y="${tick.y + 4}" text-anchor="end">${Math.round(tick.value / 100) / 10}k</text>
    </g>
  `).join("");

  els.chartHost.innerHTML = `
    <svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="PriceLabs vs market chart">
      ${yLabels}
      <polygon points="${bandTop} ${bandBottom}" fill="rgba(0,109,111,0.12)"></polygon>
      <polyline points="${marketLine}" fill="none" stroke="#006d6f" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"></polyline>
      <polyline points="${priceLabsLine}" fill="none" stroke="#d36644" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"></polyline>
      ${rows.map((row, index) => `
        <circle cx="${xForIndex(index)}" cy="${yForValue(row.marketMedian)}" r="3.5" fill="#006d6f"></circle>
        <circle cx="${xForIndex(index)}" cy="${yForValue(row.priceLabs)}" r="3.5" fill="#d36644"></circle>
      `).join("")}
      ${xLabels}
    </svg>
  `;
}

function renderDatasetEditor() {
  els.datasetEditor.value = JSON.stringify(state.dataset, null, 2);
}

function renderAll() {
  renderStatus();
  renderSubject();
  renderSummary();
  renderInsights();
  renderComparables();
  renderDailyTable();
  renderSources();
  renderChart();
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

async function runAudit(dataset) {
  const analysis = await requestJson("/api/analyze", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      dataset,
      options: getCurrentOptions(),
    }),
  });
  state.dataset = dataset;
  state.analysis = analysis;
  renderAll();
}

async function refreshSources() {
  els.refreshSources.disabled = true;
  els.refreshSources.textContent = "Refreshing...";
  try {
    state.publicIntel = await requestJson("/api/refresh-sources", { method: "POST" });
    renderSources();
  } finally {
    els.refreshSources.disabled = false;
    els.refreshSources.textContent = "Refresh PriceLabs public sources";
  }
}

function wireControls() {
  [els.horizonDays, els.minimumRating, els.maxWalkMinutes, els.minSimilarity].forEach((input) => {
    input.addEventListener("input", syncControlLabels);
  });

  els.runAnalysis.addEventListener("click", async () => {
    try {
      await runAudit(state.dataset);
    } catch (error) {
      window.alert(error.message);
    }
  });

  els.applyDataset.addEventListener("click", async () => {
    try {
      const dataset = JSON.parse(els.datasetEditor.value);
      await runAudit(dataset);
    } catch (error) {
      window.alert(`Could not analyze dataset: ${error.message}`);
    }
  });

  els.loadSample.addEventListener("click", async () => {
    state.dataset = cloneJson(state.sampleDataset);
    renderDatasetEditor();
    try {
      await runAudit(state.dataset);
    } catch (error) {
      window.alert(error.message);
    }
  });

  els.scrapeListing.addEventListener("click", async () => {
    const url = window.prompt("Paste a public listing URL to scrape:");
    if (!url || !url.trim()) { return; }

    els.scrapeListing.disabled = true;
    els.scrapeListing.textContent = "Scraping...";
    try {
      const payload = await requestJson("/api/scrape-listing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: url.trim() }),
      });

      const scraped = payload.listing || payload;
      state.dataset = state.dataset || {};
      state.dataset.subjectListing = {
        ...state.dataset.subjectListing,
        ...scraped,
        market: state.dataset.subjectListing?.market || state.dataset.meta?.microMarket || "",
        notes: state.dataset.subjectListing?.notes || [],
      };
      renderDatasetEditor();

      try {
        await runAudit(state.dataset);
      } catch (error) {
        window.alert(`Scraped listing metadata, but audit failed: ${error.message}`);
      }
    } catch (error) {
      window.alert(`Could not scrape listing: ${error.message}`);
    } finally {
      els.scrapeListing.disabled = false;
      els.scrapeListing.textContent = "Scrape listing metadata";
    }
  });

  els.refreshSources.addEventListener("click", async () => {
    try {
      await refreshSources();
    } catch (error) {
      window.alert(error.message);
    }
  });
}

async function bootstrap() {
  const payload = await requestJson("/api/bootstrap");
  state.sampleDataset = payload.dataset;
  state.dataset = cloneJson(payload.dataset);
  state.analysis = payload.analysis;
  state.publicIntel = payload.publicIntel;
  applyOptionsToControls(payload.defaultOptions);
  renderDatasetEditor();
  renderAll();
  wireControls();
}

bootstrap().catch((error) => {
  els.statusTitle.textContent = "Load failed";
  els.statusHeadline.textContent = error.message;
});
