# Universe Filter Report - 2026-07-06

## Purpose

Rank the EQ and ETF universe using both weekly recommendation approaches:

1. SMADelta, LODeltaSignal, and Combined Signal trend analysis.
2. Momentum signal analysis from `jstockdata_reco_momentum_signal`.

This report creates practical keep/omit lists for a focused weekly trading universe of top 500 or top 1000 scrips.

## Source Data

- Universe: `jstockdata_scrips` where `AssetClass IN ('EQ','ETF')`
- Trend: latest `jstockdata_hatrend_extend` DAILY and WEEKLY rows
- Momentum: current `jstockdata_reco_momentum_signal` DAILY and WEEKLY rows
- Liquidity: latest DAILY `jstockdata_hatrend` close x volume

Latest source dates:

| source_frequency | latest_date |
| --- | --- |
| DAILY | 20260702 |
| WEEKLY | 20260629 |
| OHLCV_DAILY | 20260702 |

## Universe Counts

| bucket | total | EQ | ETF |
| --- | --- | --- | --- |
| All | 1364 | 500 | 864 |
| Keep Top 500 | 500 | 220 | 280 |
| Omit If Top 500 | 864 | 280 | 584 |
| Keep Top 1000 | 1000 | 370 | 630 |
| Omit If Top 1000 | 364 | 130 | 234 |

## Scoring Method

Final `universe_score` = 38% trend + 42% momentum + 12% source rank + 8% latest liquidity.

- Trend favors BUY Combined Signal, BUY LODeltaSignal, and positive SMADeltaTrend, with WEEKLY weighted above DAILY.
- Momentum favors bullish direction, `BULLISH_ACCELERATING` or `EARLY` phase, higher confidence, positive predicted returns, and lower reversal/exhaustion risk.
- Source rank assumes lower `jstockdata_scrips.Rank` is better.
- Liquidity uses latest daily close x volume as a practical tradability tie breaker.

Score cutoffs:

| cutoff | universe_score |
| --- | --- |
| Top 500 cutoff | 72.1386 |
| Top 1000 cutoff | 52.1323 |

## Top 20 Scrips

| rank | scrip | assetclass | score | weekly_combined | weekly_momentum_phase | daily_momentum_phase |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | APP | EQ | 95.6862 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 2 | COF | EQ | 94.6141 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 3 | IBM | EQ | 94.3245 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 4 | PGR | EQ | 93.9733 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 5 | LLY | EQ | 93.9595 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 6 | BRK-B | EQ | 93.8361 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 7 | KO | EQ | 93.7226 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 8 | JNJ | EQ | 93.66 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 9 | WELL | EQ | 93.636 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 10 | BAC | EQ | 93.4428 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 11 | UNH | EQ | 93.3841 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 12 | DASH | EQ | 93.284 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 13 | DE | EQ | 93.2559 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 14 | V | EQ | 93.2164 | BUY | BULLISH_ACCELERATING | EARLY |
| 15 | MCO | EQ | 93.1719 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 16 | MRK | EQ | 92.9084 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 17 | LIN | EQ | 92.8909 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 18 | ABBV | EQ | 92.8876 | BUY | BULLISH_ACCELERATING | EARLY |
| 19 | GEV | EQ | 92.8068 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |
| 20 | SBUX | EQ | 92.7571 | BUY | BULLISH_ACCELERATING | BULLISH_ACCELERATING |

## Output Files

- `Universe_Filter_Ranked_All_20260706.csv`
- `Universe_Filter_Keep_Top500_20260706.csv`
- `Universe_Filter_Keep_Top1000_20260706.csv`
- `Universe_Filter_Omit_If_Top500_20260706.csv`
- `Universe_Filter_Omit_If_Top1000_20260706.csv`

## Recommended Use

Use Top 1000 as the normal research universe because it retains broad ETF coverage and most ranked equities. Use Top 500 for tighter weekly selection when the goal is fewer, higher-conviction candidates. Treat the omit files as screening exclusions, not permanent removals; rerun after each weekly refresh.
