import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const dir = "D:/Codex/Projects/JStockGenie/JStockGenie - 04.Robinhood Analysis/position_review_20260718";
const blob = await FileBlob.load(`${dir}/Investment_Position_Review_20260718.xlsx`);
const wb = await SpreadsheetFile.importXlsx(blob);
for (const sheetName of ["Summary", "Robinhood Options", "Robinhood Stocks", "Fidelity Stocks"]) {
  const preview = await wb.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(`${dir}/${sheetName.replaceAll(" ", "_")}_preview.png`, new Uint8Array(await preview.arrayBuffer()));
  console.log(sheetName);
}
