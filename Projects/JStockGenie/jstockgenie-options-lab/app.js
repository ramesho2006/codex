let shortlist = [
  ['AAPL','BULLISH','EQT',356.27],['AAPU','BULLISH','LEQT',49.81],['ABBV','BULLISH','EQT',295.03],['AMZN','BULLISH','EQT',266.66],['AMZZ','BULLISH','LEQT',35.47],['BLK','BULLISH','EQT',1222.91],['BRK-B','BULLISH','EQT',592.94],['CB','BULLISH','EQT',375.74],['COST','BULLISH','EQT',1106.21],['DIS','BULLISH','EQT',118.97],['FAS','BULLISH','LETF',181.54],['IHE','BULLISH','ETF',111.03],['IWD','BULLISH','ETF',263.31],['JNJ','BULLISH','EQT',285.75],['KO','BULLISH','EQT',99.25],['LIN','BULLISH','EQT',526.06],['LLY','BULLISH','EQT',1443.50],['RSPH','BULLISH','ETF',41.03],['TXN','BULLISH','EQT',303.60],['VRTX','BULLISH','EQT',538.60],['CONL','BEARISH','LETF',2.47],['ETHU','BEARISH','LETF',15.25],['MSTU','BEARISH','LETF',19.15]
].map(([symbol,direction,assetClass,close]) => ({symbol,direction,assetClass,close}));

const state = { strategy: 'CASH_SECURED_PUT', universe: 'all', analyzed: [], loading: false, orderRows: new Map(), activeOrder: null, previewedOrder: null, columnSort: { key: null, direction: 'asc' } };
const $ = (id) => document.getElementById(id);
const selectedAssetClasses = () => new Set([...document.querySelectorAll('input[name="asset-class"]:checked')].map(x => x.value));
const selectedScrips = () => { const assetClasses = selectedAssetClasses(); const universe = shortlist.filter(x => (state.universe === 'all' || x.direction === state.universe) && assetClasses.has(x.assetClass)); const entered = $('scrip-filter')?.value.trim(); if (!entered) return universe; const requested = new Set(entered.split(',').map(x => x.trim().toUpperCase()).filter(Boolean)); return universe.filter(x => requested.has(x.symbol)); };
function syncAssetClassSummary() { const chosen=[...selectedAssetClasses()]; $('asset-class-summary').textContent=chosen.length===4?'All':chosen.length?chosen.join(', '):'None'; }
function applyShortlist(rows) { shortlist = rows.map(row => ({ symbol: row.symbol, direction: row.direction, assetClass: row.assetClass, close: row.close ?? null })); $('universe-count').textContent=shortlist.length; document.querySelector('[data-universe="BULLISH"] span').textContent=shortlist.filter(x=>x.direction==='BULLISH').length; document.querySelector('[data-universe="BEARISH"] span').textContent=shortlist.filter(x=>x.direction==='BEARISH').length; }
const fmtMoney = (n) => n == null || Number.isNaN(Number(n)) ? '—' : `$${Number(n).toFixed(2)}`;
const fmtPct = (n) => n == null || Number.isNaN(Number(n)) ? '—' : `${Number(n).toFixed(1)}%`;
const strategyName = { CASH_SECURED_PUT:'Cash-secured put', COVERED_CALL:'Covered call', BULL_PUT_CREDIT_SPREAD:'Bull put spread', BEAR_CALL_CREDIT_SPREAD:'Bear call spread' };
const strategySubtitle = { CASH_SECURED_PUT:'Long-bias shortlist · sell puts below the current price', COVERED_CALL:'Long-bias shortlist · sell calls above the current price', BULL_PUT_CREDIT_SPREAD:'Bullish shortlist · sell a put and buy a lower put', BEAR_CALL_CREDIT_SPREAD:'Bearish shortlist · sell a call and buy a higher call' };

function setStatus(kind, text) { $('status-banner').className = `status-banner ${kind}`; $('status-banner').innerHTML = `<span class="status-symbol">${kind === 'error' ? '!' : kind === 'loading' ? '…' : 'i'}</span><span>${text}</span>`; }
function filters() { return { minDte: Number($('min-dte').value) || 0, maxDte: Math.min(120, Number($('max-dte').value) || 120), minPop: Number($('min-pop').value) || 0, minReturn: Number($('min-return').value) || 0, maxCollateral: Number($('max-collateral').value) || 0, top: Math.max(1, Number($('top-limit').value) || 1), sort: $('sort-by').value }; }
function renderShell() { $('table-title').textContent = `${strategyName[state.strategy]} candidates`; $('table-subtitle').textContent = strategySubtitle[state.strategy]; $('summary-shortlist').textContent = selectedScrips().length; $('summary-dte').textContent = filters().minDte; }
function compareColumnValues(a, b, key) {
  const value = row => key === 'legs' ? (row.legs || []).map(leg => `${leg.action} ${leg.type} ${leg.strike}`).join(' / ') : row[key];
  const left = value(a), right = value(b);
  const leftMissing = left == null || left === '';
  const rightMissing = right == null || right === '';
  if (leftMissing || rightMissing) return leftMissing && rightMissing ? 0 : leftMissing ? 1 : -1;
  if (typeof left === 'number' || typeof right === 'number') return Number(left) - Number(right);
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: 'base' });
}
function sortRows(rows) {
  const f=filters();
  const filtered=rows.filter(r => (r.dte ?? -1) >= f.minDte && (r.dte ?? 9999) <= f.maxDte && (r.popPct ?? -1) >= f.minPop && (r.returnPct ?? -1) >= f.minReturn && (!f.maxCollateral || (r.collateral ?? Number.POSITIVE_INFINITY) <= f.maxCollateral));
  let sorted=[...filtered];
  if (state.columnSort.key) {
    const direction = state.columnSort.direction === 'asc' ? 1 : -1;
    sorted.sort((a,b) => compareColumnValues(a,b,state.columnSort.key) * direction);
  } else if (f.sort !== 'original') {
    sorted.sort((a,b) => f.sort==='symbol' ? a.symbol.localeCompare(b.symbol) : f.sort==='dte' ? a.dte-b.dte : f.sort==='return' ? (b.returnPct||-999)-(a.returnPct||-999) : (b.popPct||-999)-(a.popPct||-999));
  }
  const count={};
  return sorted.filter(r => { count[r.symbol]=(count[r.symbol]||0)+1; return count[r.symbol] <= f.top; });
}
function renderSortIndicators() {
  document.querySelectorAll('.sortable-header').forEach(header => {
    const active = state.columnSort.key === header.dataset.sortKey;
    header.setAttribute('aria-sort', active ? (state.columnSort.direction === 'asc' ? 'ascending' : 'descending') : 'none');
    header.querySelector('.sort-indicator').textContent = active ? (state.columnSort.direction === 'asc' ? '▲' : '▼') : '↕';
  });
}
function toggleColumnSort(key) {
  if (state.columnSort.key === key) state.columnSort.direction = state.columnSort.direction === 'asc' ? 'desc' : 'asc';
  else state.columnSort = { key, direction: 'asc' };
  renderResults();
}

const orderKey = row => `${row.symbol}|${row.strategy}|${row.expiry}|${(row.legs || []).map(leg => leg.optionSymbol || leg.strike).join('|')}`;
const orderPrice = row => row.strategy.includes('SPREAD') ? row.credit : row.bid;
const orderSideLabel = row => row.strategy === 'CASH_SECURED_PUT' ? 'SELL PUT' : row.strategy === 'COVERED_CALL' ? 'SELL CALL' : row.strategy === 'BULL_PUT_CREDIT_SPREAD' ? 'BULL PUT CREDIT SPREAD' : 'BEAR CALL CREDIT SPREAD';
function setOrderStatus(kind, text) { $('order-status').className = `order-status ${kind}`; $('order-status').textContent = text; }
function buildPaperOrder(row) {
  return {
    strategy: row.strategy,
    symbol: row.symbol,
    quantity: 1,
    price: Number($('order-price').value),
    orderType: 'limit',
    duration: $('order-duration').value,
    coveredSharesConfirmed: $('covered-shares-confirmed').checked,
    confirmPaperOnly: $('paper-only-confirmed').checked,
    legs: (row.legs || []).map(leg => ({ optionSymbol: leg.optionSymbol, side: leg.side, quantity: 1 }))
  };
}
function resetOrderDialog(row) {
  state.activeOrder = row;
  state.previewedOrder = null;
  $('order-summary').textContent = `${row.symbol} · ${orderSideLabel(row)} · ${row.expiry} · ${row.dte} DTE · ${row.legs.map(leg => `${leg.action} ${leg.type} $${Number(leg.strike).toFixed(2)}`).join(' / ')}`;
  $('order-price').value = Number(orderPrice(row) || 0).toFixed(2);
  $('covered-confirmation').classList.toggle('hidden', row.strategy !== 'COVERED_CALL');
  $('covered-shares-confirmed').checked = false;
  $('paper-only-confirmed').checked = false;
  $('place-order-button').disabled = true;
  setOrderStatus('info', 'Preview the order before submitting it.');
}
async function previewPaperOrder() {
  if (!state.activeOrder) return;
  try {
    setOrderStatus('loading', 'Sending paper-order preview to Tradier Sandbox…');
    const response = await fetch('/api/paper-order/preview', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(buildPaperOrder(state.activeOrder)) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Paper-order preview failed.');
    state.previewedOrder = buildPaperOrder(state.activeOrder);
    $('place-order-button').disabled = false;
    setOrderStatus('info', 'Preview accepted by Tradier Sandbox. Review the limit price and confirmations before placing.');
  } catch (error) { setOrderStatus('error', error.message); }
}
async function placePaperOrder() {
  if (!state.activeOrder || !state.previewedOrder) return;
  const order = buildPaperOrder(state.activeOrder);
  if (JSON.stringify(order) !== JSON.stringify(state.previewedOrder)) { setOrderStatus('error', 'The order changed after preview. Preview it again.'); $('place-order-button').disabled = true; return; }
  try {
    setOrderStatus('loading', 'Submitting paper order to Tradier Sandbox…');
    const response = await fetch('/api/paper-order/place', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(order) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Paper order was rejected.');
    const orderId = data.response?.order?.id || data.response?.order?.id?.[0];
    setOrderStatus('info', orderId ? `Paper order submitted. Order ID ${orderId}. Checking status…` : 'Paper order submitted to Tradier Sandbox.');
    $('place-order-button').disabled = true;
    if (orderId) {
      const statusResponse = await fetch(`/api/paper-order/status?orderId=${encodeURIComponent(orderId)}`);
      const statusData = await statusResponse.json();
      if (statusResponse.ok) {
        const orderStatus = statusData.order?.status || statusData.order?.order?.status || 'submitted';
        setOrderStatus('info', `Paper order ${orderId}: ${orderStatus}.`);
      }
    }
  } catch (error) { setOrderStatus('error', error.message); }
}

function rowHtml(r) {
  const dir = r.direction === 'BEARISH' ? 'bearish' : 'bullish';
  const legs = (r.legs || []).map(l => `${l.action} ${l.type} ${fmtMoney(l.strike)}`).join('<br>');
  const result = r.popPct == null ? '—' : `<span class="positive">${fmtPct(r.popPct)}</span>`;
  const ret = r.returnPct == null ? '—' : `<span class="positive">${fmtPct(r.returnPct)}</span>`;
  const annualized = r.annualizedReturnPct == null ? '—' : `<span class="positive">${fmtPct(r.annualizedReturnPct)}</span>`;
  return `<tr><td class="symbol-cell"><strong>${r.symbol}</strong></td><td>${r.assetClass || '—'}</td><td><span class="direction ${dir}">${r.direction}</span></td><td>${fmtMoney(r.price)}</td><td class="strategy-label">${strategyName[r.strategy]}</td><td>${r.expiry || '—'}</td><td>${r.dte ?? '—'}</td><td class="legs">${legs || '—'}</td><td>${fmtMoney(r.premiumPerContract)}</td><td>${fmtMoney(r.collateral)}</td><td>${result}</td><td>${ret}</td><td>${annualized}</td><td>${fmtMoney(r.breakeven)}</td><td><span class="badge">${r.source || 'Tradier'}</span></td><td><button type="button" class="trade-button" data-trade-key="${encodeURIComponent(orderKey(r))}">Paper order</button></td></tr>`;
}
function renderResults() {
  renderShell(); const selected = new Set(selectedScrips().map(x => x.symbol)); const rows=sortRows(state.analyzed.filter(r=>r.strategy===state.strategy && selected.has(r.symbol))); state.orderRows = new Map(rows.map(row => [orderKey(row), row])); $('summary-results').textContent=rows.length;
  $('results-body').innerHTML = rows.length ? rows.map(rowHtml).join('') : '<tr><td colspan="16" class="empty-cell">No Tradier option rows match the current filters. Try another strategy, symbol universe, DTE range, or filter threshold.</td></tr>';
  renderSortIndicators();
}

async function analyze() {
  if (state.loading) return; state.columnSort = { key: null, direction: 'asc' }; $('sort-by').value='original'; const forceRefresh=$('force-refresh').checked; const refreshShortlist=$('refresh-shortlist').checked; let symbols=selectedScrips(); if (!symbols.length && !refreshShortlist) { setStatus('error', 'No shortlisted scrips match the scrip filter and selected universe.'); return; } state.loading=true; $('analyze-button').disabled=true;
  try {
    let sqlNote='';
    if (refreshShortlist) { setStatus('loading', 'Refreshing shortlisted scrips from MySQL…'); const universeResponse=await fetch('/api/shortlist?forceRefresh=1'); const universeData=await universeResponse.json(); if(!universeResponse.ok) throw new Error(universeData.error||'SQL shortlist refresh failed'); applyShortlist(universeData.shortlist||[]); symbols=selectedScrips(); if(!symbols.length) throw new Error('The SQL screeners returned no scrips matching the current filters.'); sqlNote=` SQL shortlist refreshed (${symbols.length} selected).`; }
    setStatus('loading', `Fetching Tradier option chains for ${symbols.length} shortlisted scrip${symbols.length===1?'':'s'}…`); const response=await fetch(`/api/analyze?strategy=${encodeURIComponent(state.strategy)}&minDte=${filters().minDte}&maxDte=${filters().maxDte}&forceRefresh=${forceRefresh?'1':'0'}&symbols=${encodeURIComponent(symbols.map(x=>x.symbol).join(','))}`); const data=await response.json(); if(!response.ok) throw new Error(data.error||'Tradier request failed'); state.analyzed=data.results||[]; $('last-updated').textContent=`Updated ${new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}`; const warning=data.errors?.length ? ` ${data.errors.length} Tradier symbol${data.errors.length===1?'':'s'} could not be loaded.` : ''; const cacheNote=data.cacheHits ? ` ${data.cacheHits} loaded from the 24-hour local cache.` : ''; const freshNote=data.fetchedSymbols ? ` ${data.fetchedSymbols} fetched from Tradier.` : ''; const refreshNote=forceRefresh?' Cache bypassed.':''; setStatus(data.errors?.length?'error':'info', `${data.results.length} option trades returned.${warning}${freshNote}${cacheNote}${refreshNote}${sqlNote} Use Top per scrip to keep the list compact.`); renderResults();
  } catch(e) { setStatus('error', e.message); } finally { state.loading=false; $('analyze-button').disabled=false; }
}
function downloadCsv() { const selected = new Set(selectedScrips().map(x => x.symbol)); const rows=sortRows(state.analyzed.filter(r=>r.strategy===state.strategy && selected.has(r.symbol))); const head=['scrip','asset_class','direction','current_close','strategy','expiry','dte','legs','premium_credit_per_contract','collateral','cop_pop_pct','return_pct','annualized_return_pct','breakeven']; const body=rows.map(r=>[r.symbol,r.assetClass,r.direction,r.price,r.strategy,r.expiry,r.dte,(r.legs||[]).map(l=>`${l.action} ${l.type} ${l.strike}`).join(' / '),r.premiumPerContract,r.collateral,r.popPct,r.returnPct,r.annualizedReturnPct,r.breakeven].map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(',')); const blob=new Blob([[head.join(','),...body].join('\n')],{type:'text/csv'}); const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`jstockgenie-options-${state.strategy.toLowerCase()}.csv`;a.click();URL.revokeObjectURL(a.href); }

document.querySelectorAll('.strategy-button').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.strategy-button').forEach(x=>x.classList.remove('active'));b.classList.add('active');state.strategy=b.dataset.strategy;renderResults();}));
document.querySelectorAll('.universe-button').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.universe-button').forEach(x=>x.classList.remove('active'));b.classList.add('active');state.universe=b.dataset.universe;renderResults();}));
['scrip-filter','min-dte','max-dte','min-pop','min-return','max-collateral','top-limit','sort-by'].forEach(id=>$(id).addEventListener('input',renderResults));
document.querySelectorAll('input[name="asset-class"]').forEach(input=>input.addEventListener('change',()=>{syncAssetClassSummary();renderResults();}));
['min-dte','max-dte','min-pop','min-return','max-collateral','top-limit','sort-by'].forEach(id=>$(id).addEventListener('change',renderResults));
 $('reset-button').addEventListener('click',()=>{ $('scrip-filter').value=''; document.querySelectorAll('input[name="asset-class"]').forEach(input=>input.checked=true); $('force-refresh').checked=false; $('refresh-shortlist').checked=false; $('min-dte').value=30; $('max-dte').value=120; $('min-pop').value=0; $('min-return').value=0; $('max-collateral').value=''; $('top-limit').value=3; $('sort-by').value='original'; state.columnSort={key:null,direction:'asc'}; syncAssetClassSummary(); renderResults(); });
$('analyze-button').addEventListener('click',analyze); $('download-button').addEventListener('click',downloadCsv);
$('sort-by').addEventListener('change', () => { state.columnSort = { key: null, direction: 'asc' }; renderResults(); });
document.querySelectorAll('.sortable-header').forEach(header => {
  header.addEventListener('click', () => toggleColumnSort(header.dataset.sortKey));
  header.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); toggleColumnSort(header.dataset.sortKey); } });
});
$('results-body').addEventListener('click', event => { const button = event.target.closest('.trade-button'); if (!button) return; const row = state.orderRows.get(decodeURIComponent(button.dataset.tradeKey)); if (!row) return; resetOrderDialog(row); $('paper-order-dialog').showModal(); });
$('close-order-button').addEventListener('click', () => $('paper-order-dialog').close());
$('preview-order-button').addEventListener('click', previewPaperOrder);
$('place-order-button').addEventListener('click', placePaperOrder);
['order-price','order-duration','covered-shares-confirmed','paper-only-confirmed'].forEach(id => $(id).addEventListener('input', () => { state.previewedOrder = null; $('place-order-button').disabled = true; }));
syncAssetClassSummary(); renderShell(); renderResults();
