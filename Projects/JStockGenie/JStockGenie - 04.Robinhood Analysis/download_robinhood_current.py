#!/usr/bin/env python
r"""Download current Robinhood equity/ETF and options data to CSV.

This is a local adaptation inspired by arungeorge101/myRobinhoodData:
https://github.com/arungeorge101/myRobinhoodData

Authentication:
  1. Prefer an environment variable:
       set RH_BEARER_TOKEN=your_token_here
  2. Or place only the token value in:
       D:\Codex\Projects\JStockGenie\JStockGenie - 04.Robinhood Analysis\token.txt

The script does not place trades. It only performs GET requests.
"""

from __future__ import annotations

import csv
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any

import requests

try:
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass


BASE_URL = "https://api.robinhood.com"
ROOT = Path(__file__).resolve().parent
OUTPUT_ROOT = ROOT / "downloads"
TOKEN_FILE = ROOT / "token.txt"


class RobinhoodDownloader:
    def __init__(self, token: str) -> None:
        self.session = requests.Session()
        self.session.headers.update(
            {
                "authorization": f"Bearer {token}",
                "accept": "application/json",
                "referer": "https://robinhood.com/",
                "x-robinhood-api-version": "1.411.9",
                "user-agent": "JStockGenie Robinhood Analysis",
            }
        )
        self.instrument_cache: dict[str, dict[str, Any]] = {}

    def get(self, url: str) -> dict[str, Any]:
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        return response.json()

    def paginated(self, path_or_url: str) -> list[dict[str, Any]]:
        url = path_or_url if path_or_url.startswith("http") else f"{BASE_URL}{path_or_url}"
        rows: list[dict[str, Any]] = []
        while url:
            payload = self.get(url)
            rows.extend(payload.get("results", []))
            url = payload.get("next")
        return rows

    def instrument(self, instrument_url: str | None) -> dict[str, Any]:
        if not instrument_url:
            return {}
        if instrument_url not in self.instrument_cache:
            self.instrument_cache[instrument_url] = self.get(instrument_url)
        return self.instrument_cache[instrument_url]


def read_token() -> str:
    token = os.environ.get("RH_BEARER_TOKEN", "").strip()
    if token:
        return token
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text(encoding="utf-8").strip()
    raise SystemExit(
        "Missing Robinhood bearer token. Set RH_BEARER_TOKEN or create token.txt in this folder."
    )


def account_last4(account_url: str | None) -> str:
    if not account_url:
        return ""
    return account_url.rstrip("/").split("/")[-1][-4:]


def money(value: Any) -> str:
    if isinstance(value, dict):
        value = value.get("amount")
    return "" if value is None else str(value)


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def flatten_equity_positions(rh: RobinhoodDownloader, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output = []
    for row in rows:
        inst = rh.instrument(row.get("instrument"))
        quantity = row.get("quantity") or row.get("shares") or ""
        if str(quantity) in ("0", "0.0000", "0.00000000"):
            continue
        output.append(
            {
                "account_last4": account_last4(row.get("account")),
                "symbol": inst.get("symbol", ""),
                "name": inst.get("simple_name") or inst.get("name", ""),
                "instrument_type": inst.get("type", ""),
                "quantity": quantity,
                "average_buy_price": money(row.get("average_buy_price")),
                "intraday_quantity": row.get("intraday_quantity", ""),
                "shares_available_for_exercise": row.get("shares_available_for_exercise", ""),
                "shares_available_for_closing_short_position": row.get(
                    "shares_available_for_closing_short_position", ""
                ),
                "raw_instrument_url": row.get("instrument", ""),
                "raw_account_url": row.get("account", ""),
            }
        )
    return output


def flatten_equity_orders(rh: RobinhoodDownloader, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output = []
    for row in rows:
        inst = rh.instrument(row.get("instrument"))
        output.append(
            {
                "account_last4": account_last4(row.get("account")),
                "symbol": inst.get("symbol", ""),
                "name": inst.get("simple_name") or inst.get("name", ""),
                "instrument_type": inst.get("type", ""),
                "created_at": row.get("created_at", ""),
                "updated_at": row.get("updated_at", ""),
                "state": row.get("state", ""),
                "side": row.get("side", ""),
                "type": row.get("type", ""),
                "time_in_force": row.get("time_in_force", ""),
                "quantity": row.get("quantity", ""),
                "cumulative_quantity": row.get("cumulative_quantity", ""),
                "average_price": row.get("average_price", ""),
                "executed_notional": money(row.get("executed_notional")),
                "fees": row.get("fees", ""),
                "cancel": row.get("cancel", ""),
                "id": row.get("id", ""),
            }
        )
    return output


def flatten_option_positions(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output = []
    for row in rows:
        quantity = row.get("quantity", "")
        if str(quantity) in ("0", "0.0000", "0.00000000"):
            continue
        output.append(
            {
                "account_last4": account_last4(row.get("account")),
                "chain_symbol": row.get("chain_symbol", ""),
                "type": row.get("type", ""),
                "option_type": row.get("option_type", ""),
                "strike_price": row.get("strike_price", ""),
                "expiration_date": row.get("expiration_date", ""),
                "quantity": quantity,
                "average_price": row.get("average_price", ""),
                "pending_buy_quantity": row.get("pending_buy_quantity", ""),
                "pending_sell_quantity": row.get("pending_sell_quantity", ""),
                "raw_option_url": row.get("option", ""),
                "raw_account_url": row.get("account", ""),
            }
        )
    return output


def flatten_option_orders(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output = []
    for row in rows:
        legs = row.get("legs") or [{}]
        first_leg = legs[0] if legs else {}
        executions = first_leg.get("executions") or [{}]
        first_execution = executions[0] if executions else {}
        output.append(
            {
                "account_last4": account_last4(row.get("account")),
                "chain_symbol": row.get("chain_symbol", ""),
                "created_at": row.get("created_at", ""),
                "updated_at": row.get("updated_at", ""),
                "state": row.get("state", ""),
                "direction": row.get("direction", ""),
                "opening_strategy": row.get("opening_strategy", ""),
                "closing_strategy": row.get("closing_strategy", ""),
                "price": row.get("price", ""),
                "processed_quantity": row.get("processed_quantity", ""),
                "processed_premium": row.get("processed_premium", ""),
                "leg_side": first_leg.get("side", ""),
                "option_type": first_leg.get("option_type", ""),
                "strike_price": first_leg.get("strike_price", ""),
                "expiration_date": first_leg.get("expiration_date", ""),
                "execution_timestamp": first_execution.get("timestamp", ""),
                "settlement_date": first_execution.get("settlement_date", ""),
                "id": row.get("id", ""),
            }
        )
    return output


def main() -> None:
    run_stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = OUTPUT_ROOT / run_stamp
    rh = RobinhoodDownloader(read_token())

    downloads: dict[str, Any] = {}

    endpoints = {
        "accounts": "/accounts/",
        "equity_positions": "/positions/?nonzero=true",
        "equity_orders": "/orders/",
        "option_positions": "/options/positions/?nonzero=true",
        "option_orders": "/options/orders/",
    }

    for name, endpoint in endpoints.items():
        downloads[name] = rh.paginated(endpoint)
        write_json(output_dir / f"{name}.json", downloads[name])

    equity_positions = flatten_equity_positions(rh, downloads["equity_positions"])
    equity_orders = flatten_equity_orders(rh, downloads["equity_orders"])
    option_positions = flatten_option_positions(downloads["option_positions"])
    option_orders = flatten_option_orders(downloads["option_orders"])

    write_csv(
        output_dir / "current_equity_etf_positions.csv",
        equity_positions,
        [
            "account_last4",
            "symbol",
            "name",
            "instrument_type",
            "quantity",
            "average_buy_price",
            "intraday_quantity",
            "shares_available_for_exercise",
            "shares_available_for_closing_short_position",
            "raw_instrument_url",
            "raw_account_url",
        ],
    )
    write_csv(
        output_dir / "equity_etf_order_history.csv",
        equity_orders,
        [
            "account_last4",
            "symbol",
            "name",
            "instrument_type",
            "created_at",
            "updated_at",
            "state",
            "side",
            "type",
            "time_in_force",
            "quantity",
            "cumulative_quantity",
            "average_price",
            "executed_notional",
            "fees",
            "cancel",
            "id",
        ],
    )
    write_csv(
        output_dir / "current_option_positions.csv",
        option_positions,
        [
            "account_last4",
            "chain_symbol",
            "type",
            "option_type",
            "strike_price",
            "expiration_date",
            "quantity",
            "average_price",
            "pending_buy_quantity",
            "pending_sell_quantity",
            "raw_option_url",
            "raw_account_url",
        ],
    )
    write_csv(
        output_dir / "option_order_history.csv",
        option_orders,
        [
            "account_last4",
            "chain_symbol",
            "created_at",
            "updated_at",
            "state",
            "direction",
            "opening_strategy",
            "closing_strategy",
            "price",
            "processed_quantity",
            "processed_premium",
            "leg_side",
            "option_type",
            "strike_price",
            "expiration_date",
            "execution_timestamp",
            "settlement_date",
            "id",
        ],
    )

    print(f"Saved Robinhood downloads to: {output_dir}")
    print(f"Current equity/ETF positions: {len(equity_positions)}")
    print(f"Equity/ETF orders: {len(equity_orders)}")
    print(f"Current option positions: {len(option_positions)}")
    print(f"Option orders: {len(option_orders)}")


if __name__ == "__main__":
    main()
