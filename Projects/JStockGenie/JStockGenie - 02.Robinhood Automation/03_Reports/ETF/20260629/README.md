# Weekly ETF Basket Routine - 20260629

Run date: 2026-06-29

Inputs:
- Growth ETFs: VUG, IWF, IVW, SCHG, SPYG, VBK, IWP, IUSG, EFG, IWO
- Dividend ETFs: VIG, VYM, SCHD, DGRO, SDY, DVY, FVD, NOBL, HDV, DGRW

Holdings source: StockAnalysis ETF holdings pages, e.g. https://stockanalysis.com/etf/vug/holdings/ .
JStockGenie context source: refreshed MySQL `reco_weekly_projection_refresh()` results.

Final outputs:
- Custom Growth Basket_20260629.csv
- Custom Dividend Basket_20260629.csv
