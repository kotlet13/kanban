// Exercise the production static link builder with a small DOM; no network.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../../website/public/assets/deletion.js', import.meta.url), 'utf8');
let submit;
let changed;
const input = { value: '', focus() {}, addEventListener(type, handler) { changed = handler; } };
const error = { textContent: '' };
const result = { hidden: true };
const link = { focus() {}, removeAttribute() { delete this.href; } };
const host = { textContent: '' };
const elements = { input, '[data-error]': error, '[data-result]': result, '[data-server-link]': link, '[data-host]': host };
const form = { dataset: { errorMessage: 'Invalid address' }, querySelector(s) { return elements[s]; }, addEventListener(type, handler) { submit = handler; } };
const network = () => { throw new Error('Unexpected network request'); };
vm.runInNewContext(source, { document: { querySelector() { return form; } }, URL, URLSearchParams, fetch: network, XMLHttpRequest: network });

for (const base of ['https://board.example.org', 'https://board.example.org/kanboard/', 'https://board.example.org:8443/path/']) {
  input.value = base;
  submit({ preventDefault() {} });
  assert.equal(result.hidden, false);
  const url = new URL(link.href);
  assert.equal(url.origin, new URL(base).origin);
  assert.equal(url.pathname, new URL(base).pathname.replace(/\/+$/, '') + '/index.php');
  assert.equal(url.searchParams.get('controller'), 'AccountDeletionController');
  assert.equal(url.searchParams.get('action'), 'index');
  assert.equal(url.searchParams.get('plugin'), 'FamilyHub');
  changed();
  assert.equal(result.hidden, true);
  assert.equal(link.href, undefined);
}
for (const invalid of ['http://board.example.org', 'javascript:alert(1)', '//board.example.org', 'https://user:password@board.example.org/', 'https://board.example.org/?session=private', 'https://board.example.org/#token', 'https://board.example.org/index.php', 'https://board.example.org/a\\b', 'https://board.example.org/a b']) {
  input.value = invalid;
  submit({ preventDefault() {} });
  assert.equal(result.hidden, true);
  assert.equal(link.href, undefined);
  assert.equal(error.textContent, 'Invalid address');
}
console.log('PASS: same-server HTTPS links, credential/query/fragment rejection, stale-link removal, no network.');
