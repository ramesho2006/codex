import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const dir = "D:/Codex/Projects/JStockGenie/JStockGenie - 04.Robinhood Analysis/position_review_20260719";

function parseCsv(text) {
  const rows = [];
  let row = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i], next = text[i + 1];
    if (quoted) {
      if (ch === '"' && next === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else {
      if (ch === '"') quoted = true;
      else if (ch === ",") { row.push(cell); cell = ""; }
      else if (ch === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
      else if (ch !== "\r") cell += ch;
    }
  }
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function coerce(v) {
  if (v === "") return null;
  if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
  return v;
}

async function readCsv(name) {
  const text = await fs.readFile(`${dir}/${name}`, "utf8");
  return parseCsv(text).map((r) => r.map(coerce));
}

function colName(n) {
  let s = "";
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - m) / 26);
  }
  return s;
}

function styleTable(sheet, range, recColLetter) {
  range.format = {
    font: { name: "Aptos", size: 10 },
    borders: { preset: "inside", style: "thin", color: "#E5E7EB" },
  };
  range.getRow(0).format = {
    fill: "#1F4E78",
    font: { bold: true, color: "#FFFFFF" },
    wrapText: true,
  };
  range.format.autofitColumns();
  range.format.autofitRows();
  sheet.freezePanes.freezeRows(1);
  sheet.showGridLines = false;
  if (recColLetter) {
    const used = sheet.getUsedRange();
    const rowCount = used.values.length;
    const recRange = sheet.getRange(`${recColLetter}2:${recColLetter}${rowCount}`);
    recRange.conditionalFormats.add("containsText", { text: "HOLD", format: { fill: "#DCFCE7", font: { color: "#166534" } } });
    recRange.conditionalFormats.add("containsText", { text: "SELL", format: { fill: "#FEE2E2", font: { color: "#991B1B" } } });
    recRange.conditionalFormats.add("containsText", { text: "ROLL", format: { fill: "#FFEDD5", font: { color: "#9A3412" } } });
    recRange.conditionalFormats.add("containsText", { text: "BUY_TO_CLOSE", format: { fill: "#FEF3C7", font: { color: "#92400E" } } });
  }
}

const summary = await readCsv("recommendation_summary.csv");
const options = await readCsv("option_recommendations.csv");
const stocks = await readCsv("stock_recommendations.csv");
const sourceRows = await readCsv("source_stock_positions.csv");
const sourceOptions = await readCsv("source_option_positions.csv");
const rhStocks = [stocks[0], ...stocks.slice(1).filter((r) => r[0] === "Robinhood")];
const fidelityStocks = [stocks[0], ...stocks.slice(1).filter((r) => r[0] === "Fidelity")];

const wb = Workbook.create();
const cover = wb.worksheets.add("Summary");
const optSheet = wb.worksheets.add("Robinhood Options");
const rhSheet = wb.worksheets.add("Robinhood Stocks");
const fidSheet = wb.worksheets.add("Fidelity Stocks");
const srcSheet = wb.worksheets.add("Source CSV");

cover.getRange("A1:H1").merge();
cover.getRange("A1").values = [["Investment Position Review"]];
cover.getRange("A1").format = { fill: "#111827", font: { bold: true, color: "#FFFFFF", size: 16 } };
cover.getRange("A3:B8").values = [
  ["As of", "2026-07-19 / latest available market close"],
  ["Source CSV", "O:\\DB001A-MYFILES\\01.Personal\\India Investments\\My Investment Positions.csv"],
  ["Market data", "Yahoo Finance via yfinance where available; CSV marks used as fallback"],
  ["Scope", "Robinhood options, Robinhood stocks, Fidelity stocks"],
  ["Key update", "Traditional IRA now includes NVDA shares and IVV shares; NVDA short call is treated as covered."],
  ["Note", "Analytical suggestions only; verify prices, tax impact, assignment risk, and account constraints before trading."],
];
cover.getRange("A3:A8").format = { fill: "#E5E7EB", font: { bold: true } };
cover.getRange("A10").write(summary);
styleTable(cover, cover.getRange(`A10:${colName(summary[0].length)}${9 + summary.length}`), null);
cover.getRange("A3:B8").format.autofitColumns();
cover.getRange("A:A").format.columnWidth = 22;
cover.getRange("B:B").format.columnWidth = 92;
cover.getRange("D:D").format.columnWidth = 26;
cover.showGridLines = false;

optSheet.getRange("A1").write(options);
styleTable(optSheet, optSheet.getRangeByIndexes(0, 0, options.length, options[0].length), "Y");

rhSheet.getRange("A1").write(rhStocks);
styleTable(rhSheet, rhSheet.getRangeByIndexes(0, 0, rhStocks.length, rhStocks[0].length), "N");

fidSheet.getRange("A1").write(fidelityStocks);
styleTable(fidSheet, fidSheet.getRangeByIndexes(0, 0, fidelityStocks.length, fidelityStocks[0].length), "N");

srcSheet.getRange("A1").write([...sourceRows, ...sourceOptions.slice(1)]);
styleTable(srcSheet, srcSheet.getRangeByIndexes(0, 0, sourceRows.length + sourceOptions.length - 1, sourceRows[0].length), null);

const errors = await wb.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
console.log(errors.ndjson);

for (const sheetName of ["Summary", "Robinhood Options", "Robinhood Stocks", "Fidelity Stocks"]) {
  const preview = await wb.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(`${dir}/${sheetName.replaceAll(" ", "_")}_preview.png`, new Uint8Array(await preview.arrayBuffer()));
}

const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(`${dir}/Investment_Position_Review_20260719.xlsx`);
console.log(`${dir}/Investment_Position_Review_20260719.xlsx`);
