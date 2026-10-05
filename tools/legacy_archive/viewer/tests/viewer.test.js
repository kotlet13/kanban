/* No browser or network: exercise actual renderer against a minimal DOM. */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const fixture = require('./fixture');
const source = fs.readFileSync(path.join(__dirname, '..', 'viewer.js'), 'utf8');
class Element {
  constructor(tag) { this.tagName = tag; this.children = []; this.listeners = {}; this.attributes = {}; this._text = ''; this.open = false; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(' '); }
  set innerHTML(_) { throw new Error('HTML injection forbidden'); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this._text = ''; this.children = children; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
  setAttribute(name, value) { this.attributes[name] = value; }
  showModal() { this.open = true; }
  close() { this.open = false; }
  dispatch(name, value) { this.value = value; this.listeners[name]?.({target: this}); }
}
function launch(data = fixture) {
  const nodes = Object.fromEntries(['content', 'capture', 'navigation', 'task-content', 'task-title', 'task-dialog', 'search', 'status', 'integrity-button', 'close-dialog'].map(id => [id, new Element('div')]));
  vm.runInNewContext(source, {window: {LEGACY_ARCHIVE: structuredClone(data)}, document: {getElementById: id => nodes[id], createElement: tag => new Element(tag)}, URL, Date, console});
  return nodes;
}
function all(node) { return [node, ...node.children.flatMap(all)]; }
function click(node, text) { const target = all(node).find(item => item.tagName === 'button' && item.textContent.includes(text)); assert.ok(target, `Missing button ${text}`); target.dispatch('click'); }
test('empty template and unsupported schema have useful read-only states', () => {
  assert.match(launch({schemaVersion: 1}).content.textContent, /Ni projektov/);
  assert.match(launch({schemaVersion: 2}).content.textContent, /nepodprto različico/);
});
test('projects include archived ones and tasks render hostile HTML as literal text', () => {
  const nodes = launch(); assert.match(nodes.content.textContent, /Arhiviran test/);
  click(nodes.content, 'Testni dom'); assert.match(nodes.content.textContent, /<img src=/);
  click(nodes.content, '#100'); assert.match(nodes['task-content'].textContent, /<script>not executed<\/script>/);
  assert.equal(all(nodes['task-content']).some(item => ['img', 'script', 'iframe'].includes(item.tagName)), false);
  assert.match(nodes['task-content'].textContent, /Zaključeno \(2\)/); assert.match(nodes['task-content'].textContent, /Evidenca časa/);
});
test('all tasks search/status preserve closed tasks from archived projects', () => {
  const nodes = launch(); click(nodes.navigation, 'Opravila'); assert.match(nodes.content.textContent, /Zaključeno testno opravilo/);
  nodes.status.dispatch('change', 'closed'); assert.doesNotMatch(nodes.content.textContent, /<img src=/);
  nodes.search.dispatch('input', 'zaključeno'); assert.match(nodes.content.textContent, /#101/);
});
test('external protocols and attachment traversal are rejected', () => {
  const data = structuredClone(fixture); data.files.push({id: 3, taskId: 100, originalName: 'traversal', path: 'attachments/%2e%2e/private.txt', status: 'ok'});
  const nodes = launch(data); click(nodes.navigation, 'Opravila'); click(nodes.content, '#100');
  const links = all(nodes['task-content']).filter(item => item.tagName === 'a');
  assert.equal(links.length, 2); assert.ok(links.some(item => item.href === 'https://example.invalid/test' && item.rel === 'noopener noreferrer'));
  assert.ok(links.some(item => item.href === 'attachments/task_has_files/1-test.txt' && item.attributes.download === 'test.txt'));
  assert.ok(links.every(item => !item.href.includes('javascript:') && !item.href.includes('..')));
  assert.match(nodes['task-content'].textContent, /missing/);
});
test('internal links open archived closed task without navigation to server', () => {
  const nodes = launch(); click(nodes.navigation, 'Opravila'); click(nodes.content, '#100'); click(nodes['task-content'], '#101');
  assert.match(nodes['task-title'].textContent, /Zaključeno testno/); assert.equal(nodes['task-dialog'].open, true);
});
test('raw tables and semantic metadata exclude security fields', () => {
  const nodes = launch(); click(nodes.navigation, 'Vse tabele');
  const select = all(nodes.content).find(item => item.tagName === 'select');
  assert.ok(select.children.every(item => item.value !== 'settings'));
  select.dispatch('change', 'users'); assert.doesNotMatch(nodes.content.textContent, /SECRET|password|api_token/);
  click(nodes.navigation, 'Projekti'); click(nodes.content, 'Testni dom'); click(nodes.content, 'Finance');
  assert.doesNotMatch(nodes.content.textContent, /SECRET-METADATA/);
});
test('finance preserves signed cents and unknown fields without rebuilding projection', () => {
  const nodes = launch(); click(nodes.content, 'Testni dom'); click(nodes.content, 'Finance');
  assert.match(nodes.content.textContent, /-12345/); assert.match(nodes.content.textContent, /56789/); assert.match(nodes.content.textContent, /unknownBusinessField/);
});
test('chunked finance works; missing/malformed/future schema has no false empty table', () => {
  const data = structuredClone(fixture); const metadata = data.tables.project_has_metadata; const text = metadata[0].value; metadata[0].value = '@chunked:2';
  metadata.push({project_id: 1, name: 'ui_finance_table_v1_chunk_0', value: text.slice(0, 40)}, {project_id: 1, name: 'ui_finance_table_v1_chunk_1', value: text.slice(40)});
  const nodes = launch(data); click(nodes.content, 'Testni dom'); click(nodes.content, 'Finance'); assert.match(nodes.content.textContent, /-12345/);
  metadata.pop(); const missing = launch(data); click(missing.content, 'Testni dom'); click(missing.content, 'Finance'); assert.match(missing.content.textContent, /Manjka del finančne/);
  metadata[0].value = '{bad'; const malformed = launch(data); click(malformed.content, 'Testni dom'); click(malformed.content, 'Finance'); assert.match(malformed.content.textContent, /Tabela ni dekodirana/);
  metadata[0].value = JSON.stringify({schemaVersion: 2}); const future = launch(data); click(future.content, 'Testni dom'); click(future.content, 'Finance'); assert.match(future.content.textContent, /Nepodprta ali neveljavna/);
});
test('integrity shows missing file and capture provenance, never claims independent verification', () => {
  const nodes = launch(); nodes['integrity-button'].dispatch('click'); assert.match(nodes.content.textContent, /Popolnost zajema še ni potrjena/);
  assert.match(nodes.content.textContent, /Sintetična manjkajoča/); assert.match(nodes.capture.textContent, /Čas kopije/);
});
test('unsafe integer finance is not presented as decoded original and raw text remains exact', () => {
  const data = structuredClone(fixture); data.tables.project_has_metadata[0].value = data.tables.project_has_metadata[0].value.replace('-12345', '9007199254740993');
  const nodes = launch(data); click(nodes.content, 'Testni dom'); click(nodes.content, 'Finance');
  assert.match(nodes.content.textContent, /zunaj natančnega obsega/); assert.match(nodes.content.textContent, /9007199254740993/);
  assert.doesNotMatch(nodes.content.textContent, /9007199254740992|Dekodirana izvirna tabela/);
});
test('project-name search and missing swimlane still show tasks without dropping records', () => {
  const data = structuredClone(fixture); delete data.tables.tasks[0].swimlane_id;
  const nodes = launch(data); nodes.search.dispatch('input', 'Testni dom'); click(nodes.content, 'Testni dom');
  assert.match(nodes.content.textContent, /#100/); assert.match(nodes.content.textContent, /Brez steze/);
});
test('chunk marker rejects JavaScript exponent and hexadecimal numeric syntax', () => {
  for (const marker of ['@chunked:1e1', '@chunked:0x10', '@chunked:+2']) {
    const data = structuredClone(fixture); data.tables.project_has_metadata[0].value = marker;
    const nodes = launch(data); click(nodes.content, 'Testni dom'); click(nodes.content, 'Finance');
    assert.match(nodes.content.textContent, /Neveljavno število delov/);
  }
});
