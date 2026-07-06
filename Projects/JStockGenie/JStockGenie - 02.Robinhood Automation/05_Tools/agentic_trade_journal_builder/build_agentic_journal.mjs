import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "D:/Codex/Projects/JStockGenie/JStockGenie - 02.Robinhood Automation/04_Journal/Agentic Trading Journal";
const outputPath = path.join(outputDir, "Robinhood_MyAgentic_Trading_Journal.xlsx");
const previewDir = path.join(outputDir, "previews");

const workbook = Workbook.create();
const journal = workbook.worksheets.add("Transaction Journal");
const pl = workbook.worksheets.add("PL Tracking");
const notes = workbook.worksheets.add("Routine Notes");
const updateLog = workbook.worksheets.add("Update Log");

const colors = {
  navy: "#17365D",
  teal: "#0F766E",
  blue: "#1D4ED8",
  green: "#008000",
  red: "#C00000",
  paleBlue: "#EAF3F8",
  paleGreen: "#E2F0D9",
  paleYellow: "#FFF2CC",
  paleRed: "#FCE4D6",
  grey: "#F2F2F2",
  border: "#D9E2F3",
};
const lastUpdatedDate = dateValue("2026-07-04");

function styleTitle(sheet, range, title) {
  const r = sheet.getRange(range);
  r.merge();
  r.values = [[title]];
  r.format = {
    fill: colors.navy,
    font: { bold: true, color: "#FFFFFF", size: 16 },
    horizontalAlignment: "left",
    verticalAlignment: "middle",
  };
}

function styleHeader(range) {
  range.format = {
    fill: colors.teal,
    font: { bold: true, color: "#FFFFFF" },
    horizontalAlignment: "center",
    verticalAlignment: "middle",
    wrapText: true,
    borders: { preset: "all", style: "thin", color: colors.border },
  };
}

function styleSection(range) {
  range.format = {
    fill: colors.paleBlue,
    font: { bold: true, color: "#000000" },
    borders: { preset: "outside", style: "thin", color: colors.border },
  };
}

function setWidths(sheet, widths) {
  widths.forEach((w, idx) => {
    sheet.getCell(0, idx).format.columnWidth = w;
  });
}

function dateValue(text) {
  return new Date(`${text}T00:00:00`);
}

// ---------------- Transaction Journal ----------------
journal.showGridLines = false;
styleTitle(journal, "A1:P1", "Agentic Trading Transaction Journal");
journal.getRange("A2:P2").values = [["Workbook generated from Robinhood Agentic account activity and weekly EQT basket routines. Amounts in USD."]];
journal.getRange("A2:P2").merge();
journal.getRange("A2:P2").format = { font: { italic: true, color: "#666666" } };

journal.getRange("A4:B9").values = [
  ["Opening Balance", 457.30405435],
  ["Funds Added", 750.0],
  ["Current Account Value", 1208.01360868],
  ["Current Cash", 807.31],
  ["Current Buying Power", 597.43],
  ["25% Cash Buffer Target", null],
];
journal.getRange("B9").formulas = [["=B6*25%"]];
styleSection(journal.getRange("A4:B9"));
journal.getRange("B4:B9").format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";
journal.getRange("A11:P11").values = [[
  "Date", "Category", "Week", "Symbol", "Side", "Status", "Qty", "Price", "Gross Amount",
  "Fees", "Cash Flow", "Cost Basis", "Realized P/L", "Order ID", "Notes", "Last Updated Date"
]];
styleHeader(journal.getRange("A11:P11"));

const journalRows = [
  [dateValue("2026-06-29"), "Opening Balance", "Start", "", "", "Recorded", null, null, null, null, 457.30405435, null, null, "", "Opening Agentic account value before first weekly rotation.", lastUpdatedDate],
  [dateValue("2026-06-30"), "Original Trade", "20260629", "AAPL", "SELL", "Filled", 0.031935, 281.07, null, 0, null, null, null, "6a433dff-3c0b-4a39-bdd1-1b709bfe5de1", "Residual position sold; avg cost basis referenced from prior position at $313.14.", lastUpdatedDate],
  [dateValue("2026-06-30"), "Original Trade", "20260629", "MAS", "BUY", "Filled", 1.244632, 80.345, null, 0, null, null, null, "6a433fd9-4d1e-4521-b7a6-83e8b5936c9f", "Initial EQT basket buy.", lastUpdatedDate],
  [dateValue("2026-06-30"), "Original Trade", "20260629", "SYF", "BUY", "Filled", 1.270488, 78.7099, null, 0, null, null, null, "6a433fdb-174f-411d-ab96-df0a501c3813", "Initial EQT basket buy.", lastUpdatedDate],
  [dateValue("2026-06-30"), "Original Trade", "20260629", "GEV", "BUY", "Filled", 0.089889, 1112.48, null, 0, null, null, null, "6a433fdd-6da9-4261-a1b1-285f21f550f3", "Initial EQT basket buy.", lastUpdatedDate],
  [dateValue("2026-06-30"), "Original Trade", "20260629", "AEP", "BUY", "Filled", 0.725531, 137.83, null, 0, null, null, null, "6a433fde-ddc0-41e0-abb7-a4e097ca3bac", "Initial EQT basket buy.", lastUpdatedDate],
  [dateValue("2026-07-04"), "Funds Added", "20260703", "", "", "Recorded", null, null, null, null, 750.0, null, null, "", "Funds added by user; inferred from account value/cash increase.", lastUpdatedDate],
  [dateValue("2026-07-04"), "New Trade", "20260703", "SYF", "SELL", "Queued", 1.270488, null, null, 0, null, null, null, "6a486ba6-267a-4c3e-af14-e7dd24528fdd", "Sell submitted for weekly rotation; fill pending.", lastUpdatedDate],
  [dateValue("2026-07-04"), "New Trade", "20260703", "GEV", "SELL", "Queued", 0.089889, null, null, 0, null, null, null, "6a486ba7-8e33-44f7-ab9b-94f0d58b1779", "Sell submitted for weekly rotation; fill pending.", lastUpdatedDate],
  [dateValue("2026-07-04"), "New Trade", "20260703", "HWM", "BUY", "Queued", 0.38807, 270.41, null, 0, null, null, null, "6a489c41-c67f-47cb-b6fd-c4edfdc53af0", "Buy submitted for weekly rotation; fill pending.", lastUpdatedDate],
  [dateValue("2026-07-04"), "New Trade", "20260703", "CASY", "BUY", "Queued", 0.13159, 797.42, null, 0, null, null, null, "6a489c43-d9e5-4f39-bc73-e0282dcdf6cb", "Buy submitted for weekly rotation; fill pending.", lastUpdatedDate],
];
journal.getRange(`A12:P${11 + journalRows.length}`).values = journalRows;

const firstData = 12;
const lastData = 11 + journalRows.length;
journal.getRange(`I${firstData}`).formulas = [["=IF(OR(G12=\"\",H12=\"\"),\"\",G12*H12)"]];
journal.getRange(`I${firstData}:I${lastData}`).fillDown();
journal.getRange(`K${firstData}`).formulas = [["=IF(B12=\"Opening Balance\",$B$4,IF(B12=\"Funds Added\",$B$5,IF(E12=\"BUY\",-(I12+J12),IF(E12=\"SELL\",I12-J12,\"\"))))"]];
journal.getRange(`K${firstData}:K${lastData}`).fillDown();
journal.getRange(`L${firstData}`).formulas = [["=IF(E12=\"BUY\",I12+J12,\"\")"]];
journal.getRange(`L${firstData}:L${lastData}`).fillDown();
journal.getRange(`M${firstData}`).formulas = [["=IF(AND(E12=\"SELL\",F12=\"Filled\",D12=\"AAPL\"),(H12-313.14)*G12,\"\")"]];
journal.getRange(`M${firstData}:M${lastData}`).fillDown();
journal.getRange(`A12:A${lastData}`).format.numberFormat = "yyyy-mm-dd";
journal.getRange(`P12:P${lastData}`).format.numberFormat = "yyyy_mm_dd";
journal.getRange(`G12:I${lastData}`).format.numberFormat = "#,##0.000000;[Red](#,##0.000000);-";
journal.getRange(`H12:M${lastData}`).format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";
journal.getRange(`A11:P${lastData}`).format.borders = { preset: "insideHorizontal", style: "thin", color: colors.border };
journal.getRange(`A12:P${lastData}`).format = { verticalAlignment: "top", wrapText: true };
journal.tables.add(`A11:P${lastData}`, true, "TransactionJournalTable");
journal.freezePanes.freezeRows(11);
setWidths(journal, [24, 18, 12, 10, 9, 11, 12, 11, 13, 9, 13, 13, 13, 38, 58, 18]);

// ---------------- P/L Tracking ----------------
pl.showGridLines = false;
styleTitle(pl, "A1:O1", "Agentic Trading P/L Tracking Since Start");
pl.getRange("A3:B10").values = [
  ["Opening Balance", 457.30405435],
  ["Funds Added", 750.0],
  ["Current Account Value", 1208.01360868],
  ["Net P/L Since Start", null],
  ["Net P/L % on Opening Balance", null],
  ["Cash", 807.31],
  ["25% Cash Buffer Target", null],
  ["Cash Buffer Status", null],
];
pl.getRange("B6").formulas = [["=B5-B3-B4"]];
pl.getRange("B7").formulas = [["=B6/B3"]];
pl.getRange("B9").formulas = [["=B5*25%"]];
pl.getRange("B10").formulas = [["=IF(B8>=B9,\"OK\",\"Below target\")"]];
styleSection(pl.getRange("A3:B10"));
pl.getRange("B3:B6").format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";
pl.getRange("B7").format.numberFormat = "0.00%;[Red](0.00%);-";
pl.getRange("B8:B9").format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";

pl.getRange("A12:O12").values = [[
  "Symbol", "Position Status", "Current Qty", "Avg Cost", "Mark Price", "Cost Basis",
  "Market Value", "Unrealized P/L", "Unrealized P/L %", "Open Order Side",
  "Open Order Qty/$", "Open Order Status", "Realized P/L Since Start", "Notes", "Last Updated Date"
]];
styleHeader(pl.getRange("A12:O12"));

const plRows = [
  ["MAS", "Open", 1.244632, 80.35, 82.77, null, null, null, null, "", "", "", 0, "Held from initial EQT basket; still in 20260703 target basket.", lastUpdatedDate],
  ["SYF", "Sell Queued", 1.270488, 78.71, 76.33, null, null, null, null, "SELL", "1.270488", "Queued", 0, "Sell submitted for rotation; realized P/L updates after fill.", lastUpdatedDate],
  ["GEV", "Sell Queued", 0.089889, 1112.48, 1119.0, null, null, null, null, "SELL", "0.089889", "Queued", 0, "Sell submitted for rotation; realized P/L updates after fill.", lastUpdatedDate],
  ["AEP", "Open", 0.725531, 137.83, 138.0, null, null, null, null, "", "", "", 0, "Held from initial EQT basket; still in 20260703 target basket.", lastUpdatedDate],
  ["HWM", "Buy Queued", 0, null, 270.41, null, null, null, null, "BUY", "$104.94", "Queued", 0, "Buy submitted for rotation; position opens after fill.", lastUpdatedDate],
  ["CASY", "Buy Queued", 0, null, 797.42, null, null, null, null, "BUY", "$104.94", "Queued", 0, "Buy submitted for rotation; position opens after fill.", lastUpdatedDate],
  ["AAPL", "Closed", 0, 313.14, 281.07, null, null, null, null, "SELL", "0.031935", "Filled", null, "Residual position closed on 2026-06-30.", lastUpdatedDate],
];
pl.getRange(`A13:O${12 + plRows.length}`).values = plRows;
const plFirst = 13;
const plLast = 12 + plRows.length;
pl.getRange(`F${plFirst}`).formulas = [["=IF(OR(C13=\"\",D13=\"\"),\"\",C13*D13)"]];
pl.getRange(`F${plFirst}:F${plLast}`).fillDown();
pl.getRange(`G${plFirst}`).formulas = [["=IF(OR(C13=\"\",E13=\"\"),\"\",C13*E13)"]];
pl.getRange(`G${plFirst}:G${plLast}`).fillDown();
pl.getRange(`H${plFirst}`).formulas = [["=IF(OR(F13=\"\",G13=\"\"),\"\",G13-F13)"]];
pl.getRange(`H${plFirst}:H${plLast}`).fillDown();
pl.getRange(`I${plFirst}`).formulas = [["=IF(F13>0,H13/F13,\"\")"]];
pl.getRange(`I${plFirst}:I${plLast}`).fillDown();
pl.getRange(`M${plFirst}`).formulas = [["=IF(A13=\"AAPL\",(281.07-313.14)*0.031935,0)"]];
pl.getRange(`M${plFirst}:M${plLast}`).fillDown();
pl.getRange(`C13:C${plLast}`).format.numberFormat = "#,##0.000000";
pl.getRange(`D13:H${plLast}`).format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";
pl.getRange(`I13:I${plLast}`).format.numberFormat = "0.00%;[Red](0.00%);-";
pl.getRange(`M13:M${plLast}`).format.numberFormat = "$#,##0.00;[Red]($#,##0.00);-";
pl.getRange(`O13:O${plLast}`).format.numberFormat = "yyyy_mm_dd";
pl.getRange(`A12:O${plLast}`).format.borders = { preset: "insideHorizontal", style: "thin", color: colors.border };
pl.getRange(`A13:O${plLast}`).format = { verticalAlignment: "top", wrapText: true };
pl.tables.add(`A12:O${plLast}`, true, "PLTrackingTable");
pl.freezePanes.freezeRows(12);
setWidths(pl, [24, 16, 12, 11, 11, 12, 12, 13, 13, 14, 15, 14, 15, 56, 18]);

// ---------------- Routine Notes ----------------
notes.showGridLines = false;
styleTitle(notes, "A1:F1", "Weekly Agentic Trading Journal Routine");
notes.getRange("A3:F3").values = [["Step", "Action", "Workbook Update", "Source", "Frequency", "Notes"]];
styleHeader(notes.getRange("A3:F3"));
const noteRows = [
  [1, "Record opening balance", "Transaction Journal summary and opening balance row", "Robinhood portfolio snapshot", "Start / reset only", "Do not overwrite historical opening balance unless resetting the strategy."],
  [2, "Record filled orders", "Add rows to Transaction Journal with filled qty, average price, fees, order id", "Robinhood order history", "Weekly", "Filled BUY rows become cost basis. Filled SELL rows compute realized P/L."],
  [3, "Record funds added/withdrawn", "Add Funds Added or Withdrawal rows", "Robinhood cash/account-value change or explicit user note", "As needed", "Current workbook includes $750.00 funds added on 2026-07-04."],
  [4, "Record new weekly rotation orders", "Add queued/submitted orders first; update to Filled once complete", "Weekly EQT Basket Routine and Robinhood order status", "Weekly", "Queued trades should not drive realized P/L until fills are known."],
  [5, "Update P/L tracking", "Refresh mark prices, positions, open order status, realized P/L", "Robinhood positions, quotes, and order status", "Weekly and after fills", "Maintain 25% cash buffer for rotations unless user overrides."],
];
notes.getRange(`A4:F${3 + noteRows.length}`).values = noteRows;
notes.getRange(`A3:F${3 + noteRows.length}`).format.borders = { preset: "insideHorizontal", style: "thin", color: colors.border };
notes.getRange(`A4:F${3 + noteRows.length}`).format = { wrapText: true, verticalAlignment: "top" };
notes.tables.add(`A3:F${3 + noteRows.length}`, true, "RoutineNotesTable");
setWidths(notes, [8, 26, 34, 34, 16, 58]);

// ---------------- Update Log ----------------
updateLog.showGridLines = false;
styleTitle(updateLog, "A1:E1", "Agentic Trading Journal Update Log");
updateLog.getRange("A3:E3").values = [["Updated Date", "Week", "Update Type", "Summary", "Source"]];
styleHeader(updateLog.getRange("A3:E3"));
const updateRows = [
  [lastUpdatedDate, "20260629", "Journal Created", "Recorded opening balance and initial filled EQT basket trades.", "Robinhood orders and 20260629 Weekly EQT Basket Routine"],
  [lastUpdatedDate, "20260703", "Weekly Rotation", "Recorded queued SYF and GEV sells plus queued HWM and CASY buys.", "Robinhood orders and 20260703 Weekly EQT Basket Routine"],
  [lastUpdatedDate, "20260703", "Funds Added", "Recorded $750.00 funds added and refreshed cash, buying power, and 25% cash buffer tracking.", "Robinhood Agentic account snapshot"],
  [lastUpdatedDate, "20260703", "Workbook Enhancement", "Renamed workbook, added Last Updated Date columns, and added this Update Log sheet.", "User request on 2026-07-04"],
];
updateLog.getRange(`A4:E${3 + updateRows.length}`).values = updateRows;
updateLog.getRange(`A4:A${3 + updateRows.length}`).format.numberFormat = "yyyy_mm_dd";
updateLog.getRange(`A3:E${3 + updateRows.length}`).format.borders = { preset: "insideHorizontal", style: "thin", color: colors.border };
updateLog.getRange(`A4:E${3 + updateRows.length}`).format = { wrapText: true, verticalAlignment: "top" };
updateLog.tables.add(`A3:E${3 + updateRows.length}`, true, "UpdateLogTable");
setWidths(updateLog, [18, 12, 22, 64, 46]);

// Workbook-wide final formatting
for (const sheet of [journal, pl, notes, updateLog]) {
  sheet.getUsedRange().format.font = { name: "Aptos", size: 10 };
  sheet.getUsedRange().format.autofitRows();
}

// Verification
const journalCheck = await workbook.inspect({
  kind: "table",
  range: "Transaction Journal!A1:P25",
  include: "values,formulas",
  tableMaxRows: 25,
  tableMaxCols: 16,
  maxChars: 5000,
});
console.log("JOURNAL_CHECK");
console.log(journalCheck.ndjson);

const plCheck = await workbook.inspect({
  kind: "table",
  range: "PL Tracking!A1:O22",
  include: "values,formulas",
  tableMaxRows: 22,
  tableMaxCols: 15,
  maxChars: 5000,
});
console.log("PL_CHECK");
console.log(plCheck.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
console.log("ERROR_SCAN");
console.log(errors.ndjson);

await fs.mkdir(previewDir, { recursive: true });
for (const sheetName of ["Transaction Journal", "PL Tracking", "Routine Notes", "Update Log"]) {
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(path.join(previewDir, `${sheetName.replaceAll(" ", "_")}.png`), new Uint8Array(await preview.arrayBuffer()));
}

await fs.mkdir(outputDir, { recursive: true });
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputPath);
console.log(`SAVED ${outputPath}`);
