import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const dir = "D:/Codex/Projects/JStockGenie/JStockGenie - 04.Robinhood Analysis/position_review_20260718";

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
    recRange.conditionalFormats.add("containsText", { text: "BUY_TO_CLOSE", format: { fill: "#FEF3C7", font: { color: "#92400E" } } });
    recRange.conditionalFormats.add("containsText", { text: "ROLL", format: { fill: "#FFEDD5", font: { color: "#9A3412" } } });
  }
}

const summary = await readCsv("recommendation_summary.csv");
const options = await readCsv("option_recommendations.csv");
const stocks = await readCsv("stock_recommendations.csv");
const rhStocks = [stocks[0], ...stocks.slice(1).filter((r) => r[0] === "Robinhood")];
const fidelityStocks = [stocks[0], ...stocks.slice(1).filter((r) => r[0] === "Fidelity")];

const wb = Workbook.create();
const cover = wb.worksheets.add("Summary");
const optSheet = wb.worksheets.add("Robinhood Options");
const rhSheet = wb.worksheets.add("Robinhood Stocks");
const fidSheet = wb.worksheets.add("Fidelity Stocks");

cover.getRange("A1:H1").merge();
cover.getRange("A1").values = [["Investment Position Review"]];
cover.getRange("A1").format = { fill: "#111827", font: { bold: true, color: "#FFFFFF", size: 16 } };
cover.getRange("A3:B7").values = [
  ["As of", "2026-07-18 / latest available market close"],
  ["Source workbook", "O:\\DB001A-MYFILES\\01.Personal\\India Investments\\My Investment Positions.xlsx"],
  ["Market data", "Yahoo Finance via yfinance where available; workbook marks used as fallback"],
  ["Scope", "Robinhood options, Robinhood stocks, Fidelity stocks"],
  ["Note", "Analytical suggestions only; verify prices, tax impact, assignment risk, and account constraints before trading."],
];
cover.getRange("A3:A7").format = { fill: "#E5E7EB", font: { bold: true } };
cover.getRange("A9").write(summary);
styleTable(cover, cover.getRange(`A9:${String.fromCharCode(64 + summary[0].length)}${8 + summary.length}`), null);
cover.getRange("A3:B7").format.autofitColumns();
cover.showGridLines = false;

optSheet.getRange("A1").write(options);
styleTable(optSheet, optSheet.getRangeByIndexes(0, 0, options.length, options[0].length), "Y");

rhSheet.getRange("A1").write(rhStocks);
styleTable(rhSheet, rhSheet.getRangeByIndexes(0, 0, rhStocks.length, rhStocks[0].length), "L");

fidSheet.getRange("A1").write(fidelityStocks);
styleTable(fidSheet, fidSheet.getRangeByIndexes(0, 0, fidelityStocks.length, fidelityStocks[0].length), "L");

const errors = await wb.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
console.log(errors.ndjson);

const preview = await wb.render({ sheetName: "Summary", autoCrop: "all", scale: 1, format: "png" });
await fs.writeFile(`${dir}/review_summary_preview.png`, new Uint8Array(await preview.arrayBuffer()));

const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(`${dir}/Investment_Position_Review_20260718.xlsx`);
console.log(`${dir}/Investment_Position_Review_20260718.xlsx`);
