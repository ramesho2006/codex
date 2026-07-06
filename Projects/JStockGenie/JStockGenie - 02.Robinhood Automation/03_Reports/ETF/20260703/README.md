# Weekly ETF Basket Routine - 20260703

Run date: 2026-07-03

SQL refresh status: skipped. `jstockdata_reco_routine_runlog` shows `reco_weekly_projection_refresh` completed successfully on 2026-07-04 01:23:29 DB time, within 1 day of this run.

Inputs:
- Growth ETFs: VUG, IWF, IVW, SCHG, SPYG, VBK, IWP, IUSG, EFG, IWO
- Dividend ETFs: VIG, VYM, SCHD, DGRO, SDY, DVY, FVD, NOBL, HDV, DGRW

Holdings source: StockAnalysis ETF holdings pages, e.g. https://stockanalysis.com/etf/vug/holdings/ .
JStockGenie context source: current MySQL reco tables.

Final outputs:
- Custom Growth Basket_20260703.csv
- Custom Dividend Basket_20260703.csv
