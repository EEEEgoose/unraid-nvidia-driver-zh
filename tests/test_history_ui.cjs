const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const page = fs.readFileSync('source/usr/local/emhttp/plugins/nvidia-driver/nvidia-driver.page', 'utf8');
const elements = {};
for (const id of ['history-search', 'history-type', 'history-status', 'history-support', 'history-download', 'history-refresh', 'toggle-gpu-driver-filter', 'gpu-driver-filter-status']) {
  elements[id] = {value: '', textContent: '', disabled: false};
}
const select = {
  options: [], selected: '',
  appendChild(option) { this.options.push(option); },
  set innerHTML(value) { this.options = []; this.selected = ''; },
  get value() { return this.selected; },
  set value(value) { this.selected = this.options.some(o => o.value === value) ? value : ''; }
};
elements['history-package'] = select;
let reply;
let fetchCount = 0;
let opened;
const context = vm.createContext({
  window: {history: {}},
  parent: {window: {location: {reload() {}}}},
  document: {
    addEventListener() {},
    getElementById(id) { return elements[id]; },
    createElement() { return {}; },
    querySelectorAll() { return []; },
    querySelector() { return null; }
  },
  fetch() { fetchCount++; return Promise.resolve({ok: true, json: () => Promise.resolve(reply)}); },
  openBox(...args) { opened = args; }
});
for (const match of page.matchAll(/<script>([\s\S]*?)<\/script>/g)) vm.runInContext(match[1], context);
const rows = [
  {name: 'nvidia-580.19-6.18.54-Unraid-1.txz', version: '580.19', type: 'nvidia', size: 1048576, installed: true, cached: true},
  {name: 'nvos-580.19-6.18.54-Unraid-1.txz', version: '580.19', type: 'nvos', size: 1048576, selected: true, cached: true},
  {name: 'nvidia-590.30-6.18.54-Unraid-1.txz', version: '590.30', type: 'nvidia', size: 1048576}
];
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  reply = {ok: true, rows, kernel: '6.18.54-Unraid'};
  context.loadHistory(false);
  await flush();
  assert.equal(select.options.length, 4);
  assert.match(select.options[1].textContent, /当前使用/);
  assert.match(select.options[2].textContent, /开源内核.*待重启.*已缓存/);
  assert.equal(fetchCount, 1); // opening the catalog does not query every driver's GPU support
  select.value = rows[1].name;
  reply = {rows: [{fetch_ok_count: 1, valid_drivers: ['580.19'], kernel_module_support: 'proprietary-only'}]};
  context.checkHistorySupport();
  assert.equal(elements['history-download'].disabled, true);
  await flush();
  assert.equal(context.historyCompatibility, 'unsupported');
  assert.equal(elements['history-download'].disabled, true);
  context.toggleGpuDriverFilter();
  assert.equal(elements['history-download'].disabled, false);
  context.downloadHistory();
  assert.match(opened[0], /arg2=nvos-580\.19-6\.18\.54-Unraid-1\.txz$/);
  context.toggleGpuDriverFilter();
  reply = {rows: [{fetch_ok_count: 0, valid_drivers: [], kernel_module_support: 'unknown'}]};
  context.checkHistorySupport();
  await flush();
  assert.equal(context.historyCompatibility, 'unknown');
  assert.equal(elements['history-download'].disabled, false);
  elements['history-type'].value = 'nvidia';
  context.renderHistoryOptions();
  assert.equal(select.options.length, 3);
  assert.equal(select.value, '');
  assert.equal(elements['history-download'].disabled, true);
  elements['history-search'].value = '590';
  context.renderHistoryOptions();
  assert.equal(select.options.length, 2);
  assert.equal(select.options[1].value, rows[2].name);
  reply = {ok: false, error: 'API 请求额度已用尽'};
  context.loadHistory(true);
  await flush();
  assert.match(elements['history-status'].textContent, /API 请求额度已用尽.*保留/);
  assert.equal(context.historyRows.length, 3);
  console.log('PASS: history search, module filters, status labels, selected-only GPU checks, unknown/incompatible states and download action');
})().catch(error => { console.error(error); process.exitCode = 1; });
