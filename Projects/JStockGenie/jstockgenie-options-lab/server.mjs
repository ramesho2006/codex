import http from 'node:http';
import { execFile, execFileSync } from 'node:child_process';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { promisify } from 'node:util';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const execFileAsync = promisify(execFile);
const chainCache = new Map();
const cacheFile = join(root, 'data', 'tradier-options-cache.json');
const cacheTtlMs = 24 * 60 * 60 * 1000;
let persistedCache = {};

try {
  persistedCache = JSON.parse(await readFile(cacheFile, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') console.warn(`Tradier cache could not be read: ${error.message}`);
}

async function savePersistedCache() {
  await mkdir(join(root, 'data'), { recursive: true });
  const temporaryFile = `${cacheFile}.tmp`;
  await writeFile(temporaryFile, JSON.stringify(persistedCache), 'utf8');
  await rename(temporaryFile, cacheFile);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readUserEnv(name) {
  if (process.env[name]) return process.env[name];
  if (process.platform !== 'win32') return '';
  try {
    const output = execFileSync('reg.exe', ['query', 'HKCU\\Environment', '/v', name], {
      encoding: 'utf8',
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'ignore']
    });
    const pattern = new RegExp(`^\\s*${escapeRegExp(name)}\\s+REG_\\S+\\s+(.*)$`, 'im');
    return output.match(pattern)?.[1]?.trim() || '';
  } catch {
    return '';
  }
}

const tradierEnvironment = (readUserEnv('TRADIER_ENV') || 'production').toLowerCase() === 'sandbox' ? 'sandbox' : 'production';
const tradierToken = readUserEnv(tradierEnvironment === 'sandbox' ? 'TRADIER_SANDBOX_API_TOKEN' : 'TRADIER_API_TOKEN');
const tradierBaseUrl = (tradierEnvironment === 'sandbox'
  ? 'https://sandbox.tradier.com/v1'
  : readUserEnv('TRADIER_API_BASE') || 'https://api.tradier.com/v1').replace(/\/+$/, '');
const sandboxBaseUrl = 'https://sandbox.tradier.com/v1';
const sandboxToken = readUserEnv('TRADIER_SANDBOX_API_TOKEN');
const sandboxAccount = readUserEnv('TRADIER_SANDBOX_ACCOUNT');

if (!tradierToken) console.warn(`Tradier ${tradierEnvironment} API token was not found in the process or Windows User environment.`);

let shortlist = new Map([
  ['AAPL', ['BULLISH', 'EQT']], ['AAPU', ['BULLISH', 'LEQT']], ['ABBV', ['BULLISH', 'EQT']], ['AMZN', ['BULLISH', 'EQT']],
  ['AMZZ', ['BULLISH', 'LEQT']], ['BLK', ['BULLISH', 'EQT']], ['BRK-B', ['BULLISH', 'EQT']], ['CB', ['BULLISH', 'EQT']],
  ['COST', ['BULLISH', 'EQT']], ['DIS', ['BULLISH', 'EQT']], ['FAS', ['BULLISH', 'LETF']], ['IHE', ['BULLISH', 'ETF']],
  ['IWD', ['BULLISH', 'ETF']], ['JNJ', ['BULLISH', 'EQT']], ['KO', ['BULLISH', 'EQT']], ['LIN', ['BULLISH', 'EQT']],
  ['LLY', ['BULLISH', 'EQT']], ['RSPH', ['BULLISH', 'ETF']], ['TXN', ['BULLISH', 'EQT']], ['VRTX', ['BULLISH', 'EQT']],
  ['CONL', ['BEARISH', 'LETF']], ['ETHU', ['BEARISH', 'LETF']], ['MSTU', ['BEARISH', 'LETF']]
]);

const num = value => {
  if (value == null || value === '') return null;
  const x = Number(String(value).replace(/[$,%+,]/g, ''));
  return Number.isFinite(x) ? x : null;
};
const asArray = value => value == null ? [] : Array.isArray(value) ? value : [value];

function tradierSymbol(symbol) {
  return symbol === 'BRK-B' ? 'BRK/B' : symbol;
}

function expiryFromContract(contractName) {
  const match = String(contractName || '').match(/(\d{6})[CP]\d+/);
  if (!match) return null;
  const value = match[1];
  return `20${value.slice(0, 2)}-${value.slice(2, 4)}-${value.slice(4, 6)}`;
}

function expiryFromOption(option) {
  const value = String(option.expiration_date || '').slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : expiryFromContract(option.symbol);
}

function daysBetween(date) {
  return Math.ceil((new Date(`${date}T16:00:00Z`) - new Date()) / 86400000);
}

function normalCdf(value) {
  const sign = value < 0 ? -1 : 1;
  const x = Math.abs(value);
  const t = 1 / (1 + 0.2316419 * x);
  const density = 0.3989423 * Math.exp(-x * x / 2);
  const polynomial = 0.319381530 * t - 0.356563782 * t * t + 1.781477937 * t * t * t - 1.821255978 * t * t * t * t + 1.330274429 * t * t * t * t * t;
  return 0.5 + sign * (0.5 - density * polynomial);
}

function estimatePop(row, price, type) {
  const sigma = Number(row.iv);
  const spot = Number(price);
  const strike = Number(row.strike);
  const dte = Number(row.dte);
  if (!Number.isFinite(sigma) || sigma <= 0 || !Number.isFinite(spot) || spot <= 0 || !Number.isFinite(strike) || strike <= 0 || !Number.isFinite(dte) || dte <= 0) return null;
  const time = dte / 365;
  const d2 = (Math.log(spot / strike) + (0.04 - 0.5 * sigma * sigma) * time) / (sigma * Math.sqrt(time));
  const probability = type === 'put' ? normalCdf(d2) : normalCdf(-d2);
  return Number((Math.max(1, Math.min(99, probability * 100))).toFixed(1));
}

function returnMetrics(premiumPerContract, collateral, dte) {
  const returnPct = premiumPerContract > 0 && collateral > 0 ? Number((premiumPerContract / collateral * 100).toFixed(2)) : null;
  const annualizedReturnPct = returnPct != null && dte > 0 ? Number((returnPct * 365 / dte).toFixed(2)) : null;
  return { returnPct, annualizedReturnPct };
}

function premiumPerContract(row) {
  const multiplier = Number(row.contractSize) > 0 ? Number(row.contractSize) : 100;
  return (row.bid ?? row.last ?? 0) * multiplier;
}

async function tradierJson(path, params = {}) {
  if (!tradierToken) throw new Error(`Tradier ${tradierEnvironment} API token is not configured.`);
  const url = new URL(`${tradierBaseUrl}/${path.replace(/^\/+/, '')}`);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, String(value));
  const response = await fetch(url, { headers: { Authorization: `Bearer ${tradierToken}`, Accept: 'application/json' } });
  const body = await response.text();
  if (!response.ok) {
    let detail = body;
    try { detail = JSON.stringify(JSON.parse(body)); } catch { /* keep the short text response */ }
    throw new Error(`Tradier ${response.status}: ${detail.slice(0, 240)}`);
  }
  try {
    return JSON.parse(body);
  } catch {
    throw new Error('Tradier returned a non-JSON response.');
  }
}

function normalizeOption(option) {
  const greeks = option.greeks || {};
  const type = String(option.option_type || '').toLowerCase();
  return {
    contractName: option.symbol || '',
    strike: num(option.strike),
    last: num(option.last),
    bid: num(option.bid),
    ask: num(option.ask),
    volume: num(option.volume),
    openInterest: num(option.open_interest),
    iv: num(greeks.mid_iv ?? greeks.smv_vol ?? greeks.bid_iv ?? greeks.ask_iv),
    contractSize: num(option.contract_size) || 100,
    type,
    greeks,
    expiry: expiryFromOption(option)
  };
}

async function readJsonBody(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 100 * 1024) throw new Error('Request body is too large.');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new Error('The order request was not valid JSON.');
  }
}

function validatePaperOrder(order, shouldPlace) {
  if (!sandboxToken || !sandboxAccount) throw new Error('Tradier Sandbox token and account are required for paper orders.');
  if (!order || !['CASH_SECURED_PUT', 'COVERED_CALL', 'BULL_PUT_CREDIT_SPREAD', 'BEAR_CALL_CREDIT_SPREAD'].includes(order.strategy)) throw new Error('Unsupported option strategy.');
  if (!/^[A-Za-z0-9./-]+$/.test(String(order.symbol || ''))) throw new Error('Invalid underlying symbol.');
  if (Number(order.quantity) !== 1) throw new Error('Paper trading is limited to one contract per order.');
  if (order.orderType !== 'limit' || order.duration !== 'day') throw new Error('Only day limit orders are enabled for paper trading.');
  if (!Number.isFinite(Number(order.price)) || Number(order.price) <= 0 || Number(order.price) > 100000) throw new Error('Enter a valid positive limit price.');
  if (!Array.isArray(order.legs) || ![1, 2].includes(order.legs.length)) throw new Error('Paper orders must contain one option leg or a two-leg spread.');
  for (const leg of order.legs) {
    if (!/^[A-Za-z0-9./-]+$/.test(String(leg.optionSymbol || ''))) throw new Error('Invalid option symbol.');
    if (!['buy_to_open', 'sell_to_open'].includes(leg.side)) throw new Error('Only opening option legs are enabled.');
    if (Number(leg.quantity) !== 1) throw new Error('Each paper leg must have quantity 1.');
  }
  if (order.strategy === 'COVERED_CALL' && order.coveredSharesConfirmed !== true) throw new Error('Confirm that the paper account holds the underlying shares before opening a covered call.');
  if (shouldPlace && order.confirmPaperOnly !== true) throw new Error('Confirm that this order is for Tradier Sandbox paper trading only.');
}

function orderForm(order, preview) {
  const form = new URLSearchParams();
  const isSpread = order.legs.length === 2;
  form.set('class', isSpread ? 'multileg' : 'option');
  form.set('symbol', order.symbol);
  form.set('quantity', '1');
  form.set('duration', 'day');
  form.set('price', String(Number(order.price)));
  form.set('type', isSpread ? 'credit' : 'limit');
  if (preview) form.set('preview', 'true');
  order.legs.forEach((leg, index) => {
    if (isSpread) {
      form.set(`option_symbol[${index}]`, leg.optionSymbol);
      form.set(`side[${index}]`, leg.side);
      form.set(`quantity[${index}]`, '1');
    } else {
      form.set('option_symbol', leg.optionSymbol);
      form.set('side', leg.side);
    }
  });
  return form;
}

async function submitPaperOrder(order, preview) {
  validatePaperOrder(order, !preview);
  const response = await fetch(`${sandboxBaseUrl}/accounts/${encodeURIComponent(sandboxAccount)}/orders`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${sandboxToken}`,
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: orderForm(order, preview)
  });
  const body = await response.text();
  let payload;
  try { payload = JSON.parse(body); } catch { payload = { raw: body.slice(0, 1000) }; }
  if (!response.ok) throw new Error(`Tradier Sandbox ${response.status}: ${JSON.stringify(payload).slice(0, 400)}`);
  const apiError = payload?.errors?.error || payload?.error;
  if (apiError) throw new Error(`Tradier Sandbox rejected the order: ${Array.isArray(apiError) ? apiError.join('; ') : apiError}`);
  return { mode: 'sandbox', preview, response: payload };
}

async function getPaperOrderStatus(orderId) {
  if (!sandboxToken || !sandboxAccount) throw new Error('Tradier Sandbox token and account are required.');
  if (!/^\d+$/.test(String(orderId))) throw new Error('Invalid paper order id.');
  const response = await fetch(`${sandboxBaseUrl}/accounts/${encodeURIComponent(sandboxAccount)}/orders/${orderId}`, {
    headers: { Authorization: `Bearer ${sandboxToken}`, Accept: 'application/json' }
  });
  const body = await response.text();
  let payload;
  try { payload = JSON.parse(body); } catch { payload = { raw: body.slice(0, 1000) }; }
  if (!response.ok) throw new Error(`Tradier Sandbox ${response.status}: ${JSON.stringify(payload).slice(0, 400)}`);
  return payload;
}

async function fetchTradierChains(symbols, minDte, maxDte, forceRefresh = false) {
  const chains = {};
  const missing = [];
  const cacheHits = [];
  const fetchedSymbols = [];

  for (const symbol of symbols) {
    const key = `${symbol}:${minDte}:${maxDte}`;
    const cached = persistedCache[key];
    if (!forceRefresh && cached && Date.now() - cached.fetchedAt < cacheTtlMs && cached.data) {
      chains[symbol] = cached.data;
      cacheHits.push(symbol);
    } else {
      missing.push(symbol);
    }
  }
  if (!missing.length) return { chains, cacheHits, fetchedSymbols };

  const quoteResponse = await tradierJson('markets/quotes', { symbols: missing.map(tradierSymbol).join(',') });
  const quoteMap = new Map(asArray(quoteResponse.quotes?.quote).map(quote => [quote.symbol, quote]));

  for (const symbol of missing) {
    const apiSymbol = tradierSymbol(symbol);
    try {
      const quote = quoteMap.get(apiSymbol) || quoteMap.get(symbol);
      if (!quote) throw new Error('underlying quote was not returned');
      const expirationResponse = await tradierJson('markets/options/expirations', { symbol: apiSymbol, includeAllRoots: true });
      const expirationDates = asArray(expirationResponse.expirations?.date).map(String);
      const eligibleDates = expirationDates.filter(date => {
        const dte = daysBetween(date);
        return dte >= minDte && dte <= maxDte;
      });
      const calls = [];
      const puts = [];
      for (const expiration of eligibleDates) {
        const chainResponse = await tradierJson('markets/options/chains', { symbol: apiSymbol, expiration, greeks: true });
        for (const option of asArray(chainResponse.options?.option)) {
          const row = normalizeOption(option);
          if (row.type === 'call') calls.push(row);
          if (row.type === 'put') puts.push(row);
        }
      }
      const data = {
        symbol,
        price: num(quote.last ?? quote.bid ?? quote.ask ?? quote.prevclose),
        calls,
        puts,
        expiries: eligibleDates,
        quoteTimestamp: quote.trade_date || quote.bid_date || quote.ask_date || null
      };
      chains[symbol] = data;
      persistedCache[`${symbol}:${minDte}:${maxDte}`] = { fetchedAt: Date.now(), data };
      fetchedSymbols.push(symbol);
    } catch (error) {
      chains[symbol] = { symbol, error: `${symbol}: ${error.message}` };
    }
  }
  await savePersistedCache();
  return { chains, cacheHits, fetchedSymbols };
}

function withMeta(row, chain, strategy) {
  const expiry = row.expiry || expiryFromContract(row.contractName);
  return {
    ...row,
    symbol: chain.symbol,
    price: chain.price,
    expiry,
    dte: expiry ? daysBetween(expiry) : null,
    direction: shortlist.get(chain.symbol)?.[0],
    assetClass: shortlist.get(chain.symbol)?.[1],
    source: 'Tradier',
    strategy
  };
}

function buildCandidates(chain, strategy, minDte, maxDte) {
  const bullish = shortlist.get(chain.symbol)?.[0] === 'BULLISH';
  if (['CASH_SECURED_PUT', 'COVERED_CALL', 'BULL_PUT_CREDIT_SPREAD'].includes(strategy) && !bullish) return [];
  if (strategy === 'BEAR_CALL_CREDIT_SPREAD' && bullish) return [];

  const rows = (strategy.includes('PUT') ? chain.puts : chain.calls)
    .map(row => withMeta(row, chain, strategy))
    .filter(row => row.expiry && row.dte >= minDte && row.dte <= maxDte);

  if (strategy === 'CASH_SECURED_PUT') {
    return rows.filter(row => row.type === 'put' && row.strike < row.price && row.bid > 0).map(row => {
      const multiplier = Number(row.contractSize) || 100;
      const collateral = row.strike * multiplier;
      const premium = premiumPerContract(row);
      return { ...row, legs: [{ action: 'SELL', type: 'PUT', strike: row.strike, optionSymbol: row.contractName, side: 'sell_to_open' }], premiumPerContract: premium, collateral, popPct: estimatePop(row, row.price, 'put'), ...returnMetrics(premium, collateral, row.dte), breakeven: row.strike - (row.bid ?? 0) };
    });
  }

  if (strategy === 'COVERED_CALL') {
    return rows.filter(row => row.type === 'call' && row.strike > row.price && row.bid > 0).map(row => {
      const multiplier = Number(row.contractSize) || 100;
      const collateral = row.price * multiplier;
      const premium = premiumPerContract(row);
      return { ...row, legs: [{ action: 'SELL', type: 'CALL', strike: row.strike, optionSymbol: row.contractName, side: 'sell_to_open' }], premiumPerContract: premium, collateral, popPct: estimatePop(row, row.price, 'call'), ...returnMetrics(premium, collateral, row.dte), breakeven: null };
    });
  }

  const options = rows
    .filter(row => bullish ? row.type === 'put' && row.strike < row.price : row.type === 'call' && row.strike > row.price)
    .sort((a, b) => bullish ? b.strike - a.strike : a.strike - b.strike);
  const out = [];
  for (let index = 0; index < options.length; index += 1) {
    const short = options[index];
    const long = options.find(candidate => candidate.expiry === short.expiry && (bullish ? candidate.strike < short.strike : candidate.strike > short.strike));
    if (!long) continue;
    const multiplier = Number(short.contractSize) || Number(long.contractSize) || 100;
    const credit = (short.bid ?? 0) - (long.ask ?? 0);
    if (credit <= 0) continue;
    const width = Math.abs(short.strike - long.strike);
    const collateral = width * multiplier;
    const creditPerContract = credit * multiplier;
    out.push({
      ...short,
      strategy,
      premiumPerContract: creditPerContract,
      credit,
      collateral,
      popPct: estimatePop(short, chain.price, short.type),
      ...returnMetrics(creditPerContract, collateral, short.dte),
      breakeven: bullish ? short.strike - credit : short.strike + credit,
      legs: [
        { action: 'SELL', type: bullish ? 'PUT' : 'CALL', strike: short.strike, optionSymbol: short.contractName, side: 'sell_to_open' },
        { action: 'BUY', type: bullish ? 'PUT' : 'CALL', strike: long.strike, optionSymbol: long.contractName, side: 'buy_to_open' }
      ]
    });
  }
  return out;
}

async function refreshShortlistFromSql() {
  const script = join(root, 'refresh_shortlist.py');
  try {
    const { stdout } = await execFileAsync('python', [script], { maxBuffer: 2 * 1024 * 1024, windowsHide: true });
    const payload = JSON.parse(stdout);
    if (!Array.isArray(payload.shortlist) || !payload.shortlist.length) throw new Error('The SQL screeners returned no shortlisted scrips.');
    shortlist = new Map(payload.shortlist.map(row => [row.symbol, [row.direction, row.assetClass, row.close ?? null]]));
    return payload.shortlist;
  } catch (error) {
    if (error instanceof SyntaxError) throw new Error('SQL shortlist refresh returned invalid JSON.');
    throw new Error(`SQL shortlist refresh failed: ${error.message.split('\n')[0]}`);
  }
}

async function analyze(url) {
  const query = new URL(url, 'http://localhost');
  const strategy = query.searchParams.get('strategy') || 'CASH_SECURED_PUT';
  const minDte = Number(query.searchParams.get('minDte') || 30);
  const requestedMaxDte = Number(query.searchParams.get('maxDte') || 120);
  const maxDte = Math.min(120, Math.max(0, requestedMaxDte));
  const forceRefresh = query.searchParams.get('forceRefresh') === '1';
  const symbols = (query.searchParams.get('symbols') || '').split(',').filter(symbol => shortlist.has(symbol));
  const results = [];
  const errors = [];
  let loaded;
  try {
    loaded = await fetchTradierChains(symbols, minDte, maxDte, forceRefresh);
  } catch (error) {
    return { results, errors: [error.message], source: `Tradier ${tradierEnvironment}`, fetchedAt: new Date().toISOString() };
  }
  for (const symbol of symbols) {
    const raw = loaded.chains[symbol];
    if (!raw || raw.error) {
      errors.push(raw?.error || `${symbol}: Tradier option chain unavailable`);
      continue;
    }
    const chain = { ...raw, direction: shortlist.get(symbol)?.[0], assetClass: shortlist.get(symbol)?.[1] };
    chainCache.set(symbol, { fetchedAt: Date.now(), data: chain });
    results.push(...buildCandidates(chain, strategy, minDte, maxDte));
  }
  return {
    results,
    errors,
    cacheHits: loaded.cacheHits.length,
    fetchedSymbols: loaded.fetchedSymbols.length,
    forceRefresh,
    source: `Tradier ${tradierEnvironment}`,
    fetchedAt: new Date().toISOString()
  };
}

const server = http.createServer(async (request, response) => {
  try {
    if (request.method === 'POST' && request.url === '/api/paper-order/preview') {
      const result = await submitPaperOrder(await readJsonBody(request), true);
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      return response.end(JSON.stringify(result));
    }
    if (request.method === 'POST' && request.url === '/api/paper-order/place') {
      const result = await submitPaperOrder(await readJsonBody(request), false);
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      return response.end(JSON.stringify(result));
    }
    if (request.method === 'GET' && request.url.startsWith('/api/paper-order/status')) {
      const query = new URL(request.url, 'http://localhost');
      const result = await getPaperOrderStatus(query.searchParams.get('orderId'));
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      return response.end(JSON.stringify(result));
    }
    if (request.url.startsWith('/api/shortlist')) {
      const query = new URL(request.url, 'http://localhost');
      const rows = query.searchParams.get('forceRefresh') === '1'
        ? await refreshShortlistFromSql()
        : [...shortlist.entries()].map(([symbol, [direction, assetClass, close]]) => ({ symbol, direction, assetClass, close }));
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      return response.end(JSON.stringify({ shortlist: rows, source: 'MySQL strong trend screeners', refreshed: query.searchParams.get('forceRefresh') === '1' }));
    }
    if (request.url.startsWith('/api/analyze')) {
      const data = await analyze(request.url);
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      return response.end(JSON.stringify(data));
    }
    const requestPath = new URL(request.url, 'http://localhost').pathname;
    const relative = requestPath === '/' ? 'index.html' : requestPath.replace(/^\/+/, '');
    const file = join(root, normalize(relative));
    const body = await readFile(file);
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
    response.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' });
    response.end(body);
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' ? 404 : 500, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ error: error.message }));
  }
});

server.listen(4173, () => console.log(`JStockGenie Options Lab running at http://localhost:4173 using Tradier ${tradierEnvironment}`));
