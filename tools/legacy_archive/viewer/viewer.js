/* Offline, read-only projection. Original backup is kept separately. */
(() => {
  'use strict';
  const archive = window.LEGACY_ARCHIVE;
  const content = document.getElementById('content');
  if (!archive || archive.schemaVersion !== 1) {
    content.textContent = 'Arhiv ni naložen ali uporablja nepodprto različico. Odpri index.html iz mape, ki jo ustvari izvoznik.';
    return;
  }
  const forbiddenTable = /^(settings|sessions|remember_me|password_reset|schema_version|user_has_notifications|user_has_metadata|oauth.*|.*tokens?|.*credentials?|.*authentication.*)$/i;
  const secretField = /password|passwd|secret|token|api[_-]?key|private[_-]?key|twofactor|two_factor|otp|authentication|csrf|session[_-]?id/i;
  const tables = Object.fromEntries(Object.entries(archive.tables || {}).filter(([name, rows]) => !forbiddenTable.test(name) && Array.isArray(rows)));
  const rows = name => tables[name] || [];
  const same = (a, b) => a !== undefined && b !== undefined && String(a) === String(b);
  const related = (name, field, id) => rows(name).filter(row => same(row[field], id));
  const find = (name, id) => rows(name).find(row => same(row.id, id));
  const ordered = items => [...items].sort((a, b) => Number(a.position || 0) - Number(b.position || 0));
  const str = value => value === null || value === undefined ? '—' : String(value);
  const state = {view: 'projects', project: null, tab: 'tasks', search: '', status: 'all', table: 'tasks', page: 0};

  function el(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined && text !== null) node.textContent = str(text);
    if (className) node.className = className;
    return node;
  }
  function button(text, action, className = 'quiet') {
    const node = el('button', text, className);
    node.type = 'button'; node.addEventListener('click', action); return node;
  }
  function empty(parent, text) { parent.append(el('p', text, 'muted empty')); }
  function section(parent, title) { const node = el('section', null, 'section'); if (title) node.append(el('h3', title)); parent.append(node); return node; }
  function sanitize(value) {
    if (Array.isArray(value)) return value.map(sanitize);
    if (value && typeof value === 'object' && secretField.test(str(value.name || value.key || ''))) return {...Object.fromEntries(Object.entries(value).filter(([key]) => !secretField.test(key) && key !== 'value')), value: '[Varnostna vrednost izključena]'};
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).filter(([key]) => !secretField.test(key)).map(([key, item]) => [key, sanitize(item)]));
    return value;
  }
  function raw(parent, value, label = 'Izvirni zapis (brez varnostnih polj)') {
    const detail = el('details'); detail.append(el('summary', label), el('pre', JSON.stringify(sanitize(value), null, 2))); parent.append(detail);
  }
  function readableDate(value) {
    if (!value || value === '0') return '—';
    const date = typeof value === 'number' || /^\d{9,}$/.test(str(value)) ? new Date(Number(value) * 1000) : new Date(value);
    return Number.isNaN(date.getTime()) ? str(value) : date.toLocaleString('sl-SI');
  }
  function person(id) { const user = find('users', id); return user ? str(user.name || user.username || `#${id}`) : id && id !== '0' ? `Uporabnik #${id}` : '—'; }
  function isOpen(task) { return Number(task.is_active) === 1; }
  function matches(record) { return !state.search || [record.id, record.name, record.title, record.description].some(value => str(value).toLocaleLowerCase('sl').includes(state.search)); }
  function filteredTasks(items = rows('tasks')) { return items.filter(task => (matches(task) || matches(find('projects', task.project_id) || {})) && (state.status === 'all' || (state.status === 'open') === isOpen(task))); }
  function badge(text, blue = false) { return el('span', text, `badge${blue ? ' blue' : ''}`); }
  function facts(parent, entries) {
    const list = el('dl', null, 'facts');
    entries.forEach(([name, value]) => { const group = el('div', null, 'fact'); group.append(el('dt', name), el('dd', value)); list.append(group); }); parent.append(list);
  }
  function safeExternal(value) {
    try { const url = new URL(str(value)); return ['https:', 'http:', 'mailto:'].includes(url.protocol) && !url.username && !url.password ? url.href : null; } catch { return null; }
  }
  function safeFilePath(value) {
    if (typeof value !== 'string' || !value.startsWith('attachments/') || /[\\\x00-\x1f?#:]/.test(value)) return null;
    try {
      const decoded = decodeURIComponent(value);
      if (/[\\\x00-\x1f?#:]/.test(decoded) || decoded.split('/').some(part => !part || part === '.' || part === '..')) return null;
      return value.split('/').map(encodeURIComponent).join('/');
    } catch { return null; }
  }
  function link(parent, title, value, file = false) {
    const href = file ? safeFilePath(value) : safeExternal(value);
    if (!href) { parent.append(el('span', `${title} · povezava ni varna ali ni podprta`, 'muted')); return; }
    const node = el('a', title); node.href = href;
    if (file) node.setAttribute('download', title); else { node.target = '_blank'; node.rel = 'noopener noreferrer'; node.referrerPolicy = 'no-referrer'; }
    parent.append(node);
  }
  function renderNavigation() {
    const nav = document.getElementById('navigation'); nav.replaceChildren();
    [['projects', 'Projekti', rows('projects').length], ['tasks', 'Opravila', rows('tasks').length], ['tables', 'Vse tabele', Object.keys(tables).length]].forEach(([view, label, count]) => {
      const node = button(label, () => { state.view = view; state.project = null; state.page = 0; render(); }, `nav-button${state.view === view ? ' active' : ''}`); node.append(el('span', count, 'count')); nav.append(node);
    });
  }
  function renderCapture() {
    const capture = document.getElementById('capture'); const integrity = archive.integrity || {};
    capture.append(badge(integrity.complete === true ? 'Zajem preverjen' : 'Popolnost še ni potrjena', integrity.complete === true));
    capture.append(el('span', `Čas kopije: ${readableDate(archive.source?.capturedAt)}`), el('span', `Izvoz: ${readableDate(archive.generatedAt)}`), el('span', `Kanboard ${str(archive.source?.kanboardVersion)}`));
  }
  function render() {
    renderNavigation(); content.replaceChildren();
    if (state.view === 'integrity') return renderIntegrity();
    if (state.view === 'tables') return renderTables();
    if (state.project !== null) return renderProject(find('projects', state.project));
    if (state.view === 'tasks') {
      content.append(el('h2', 'Vsa opravila'), el('p', 'Vključena so odprta in zaključena opravila, tudi iz arhiviranih projektov.', 'muted'));
      return taskList(section(content), filteredTasks());
    }
    content.append(el('h2', 'Projekti'), el('p', 'Ohranjena struktura starega sistema. Arhiv ne uvaža podatkov v novi organizator.', 'muted'));
    const grid = el('div', null, 'grid'); content.append(grid);
    const projects = rows('projects').filter(project => matches(project) || (state.search && related('tasks', 'project_id', project.id).some(matches)));
    if (!projects.length) return empty(grid, 'Ni projektov za ta prikaz. Preveri iskanje ali podatke o zajemu.');
    projects.forEach(project => {
      const tasks = related('tasks', 'project_id', project.id); const node = button('', () => openProject(project.id), 'project-card');
      node.append(el('strong', project.name || `Projekt #${project.id}`), badge(Number(project.is_active) === 1 ? 'Aktiven projekt' : 'Arhiviran projekt'), el('span', `${tasks.filter(isOpen).length} odprtih · ${tasks.filter(task => !isOpen(task)).length} zaključenih opravil`, 'muted'));
      if (project.description) node.append(el('p', project.description, 'muted prose')); grid.append(node);
    });
  }
  function openProject(id) { state.project = id; state.view = 'projects'; state.tab = 'tasks'; state.page = 0; render(); }
  function taskCard(task) {
    const node = el('div', null, 'task-card'); node.append(button(`#${task.id} · ${task.title || 'Brez naslova'}`, () => openTask(task), 'link-button'));
    node.append(badge(isOpen(task) ? 'Odprto' : 'Zaključeno', isOpen(task)), el('span', `${person(task.owner_id)} · rok ${readableDate(task.date_due)}`, 'muted')); return node;
  }
  function taskList(parent, tasks) {
    if (!tasks.length) return empty(parent, 'Ni opravil za izbrane filtre.');
    const pageSize = 100; const maxPage = Math.max(0, Math.ceil(tasks.length / pageSize) - 1); state.page = Math.min(state.page, maxPage);
    tasks.slice(state.page * pageSize, (state.page + 1) * pageSize).forEach(task => {
      const row = el('div', null, 'row'); const title = el('div'); title.append(button(`#${task.id} · ${task.title}`, () => openTask(task), 'link-button'));
      const project = find('projects', task.project_id); title.append(el('p', `${project?.name || `Projekt #${task.project_id}`} · ${person(task.owner_id)} · rok ${readableDate(task.date_due)}`, 'muted')); row.append(title, badge(isOpen(task) ? 'Odprto' : 'Zaključeno', isOpen(task))); parent.append(row);
    });
    pagination(parent, tasks.length, pageSize, maxPage);
  }
  function pagination(parent, count, size, maxPage) {
    if (count <= size) return;
    const node = el('div', null, 'pagination'); const previous = button('Prejšnja', () => { state.page--; render(); }); previous.disabled = state.page === 0;
    const next = button('Naslednja', () => { state.page++; render(); }); next.disabled = state.page === maxPage;
    node.append(previous, el('span', `${state.page + 1} / ${maxPage + 1} · ${count} zapisov`, 'muted'), next); parent.append(node);
  }
  function renderProject(project) {
    if (!project) return empty(content, 'Projekt ni v izvozu.');
    content.append(button('← Vsi projekti', () => { state.project = null; state.page = 0; render(); }), el('p'), el('h2', project.name));
    content.append(badge(Number(project.is_active) === 1 ? 'Aktiven projekt' : 'Arhiviran projekt'));
    if (project.description) content.append(el('p', project.description, 'prose muted'));
    const toolbar = el('div', null, 'toolbar'); content.append(el('p'), toolbar);
    [['tasks', 'Tabla in opravila'], ['details', 'Podrobnosti'], ['finance', 'Finance'], ['files', 'Priponke']].forEach(([tab, title]) => toolbar.append(button(title, () => { state.tab = tab; state.page = 0; render(); }, `quiet${state.tab === tab ? ' active' : ''}`)));
    if (state.tab === 'files') return fileList(section(content, 'Projektne in opravilne priponke'), (archive.files || []).filter(file => same(file.projectId, project.id) || same(find('tasks', file.taskId)?.project_id, project.id)));
    if (state.tab === 'finance') return renderFinance(project);
    if (state.tab === 'details') {
      facts(section(content, 'Projekt'), [['Številka', project.id], ['Ustvarjen', readableDate(project.creation_date)], ['Spremenjen', readableDate(project.last_modified)], ['Zadnja dejavnost', readableDate(project.last_activity)]]);
      const members = section(content, 'Članstva, skupine in pravila');
      ['project_has_users', 'project_has_groups', 'project_has_roles', 'project_has_categories', 'project_has_metadata'].forEach(table => raw(members, related(table, 'project_id', project.id), table));
      const activity = section(content, 'Dejavnosti in prehodi'); ['project_activities', 'transitions'].forEach(table => raw(activity, related(table, 'project_id', project.id), table)); raw(content, project); return;
    }
    const tasks = filteredTasks(related('tasks', 'project_id', project.id));
    const columns = ordered(related('columns', 'project_id', project.id)); const lanes = ordered(related('swimlanes', 'project_id', project.id));
    if (!columns.length || tasks.length > 500) {
      if (tasks.length > 500) content.append(el('p', 'Za veliko zbirko je prikazan seznam s stranmi. Izvirne lokacije so v podrobnostih opravila.', 'muted'));
      return taskList(section(content, 'Opravila'), tasks);
    }
    const laneKey = value => value === undefined || value === null ? '0' : str(value);
    const laneIds = [...new Set([...lanes.map(lane => laneKey(lane.id)), ...tasks.map(task => laneKey(task.swimlane_id))])];
    if (!laneIds.length) laneIds.push('0');
    laneIds.forEach(id => {
      const lane = lanes.find(item => same(item.id, id)); const group = section(content, lane?.name || (id === '0' ? 'Brez steze' : `Steza #${id} ni v izvozu`)); const board = el('div', null, 'board'); group.append(board);
      columns.forEach(column => {
        const col = el('div', null, 'board-column'); col.append(el('h3', column.title || `Stolpec #${column.id}`)); board.append(col);
        const items = ordered(tasks.filter(task => same(task.column_id, column.id) && laneKey(task.swimlane_id) === id));
        items.forEach(task => col.append(taskCard(task))); if (!items.length) empty(col, 'Ni opravil.');
      });
    });
    const unmatched = tasks.filter(task => !columns.some(column => same(column.id, task.column_id)));
    if (unmatched.length) taskList(section(content, 'Opravila brez najdenega stolpca'), unmatched);
  }
  function fileList(parent, files) {
    if (!files.length) return empty(parent, 'Ni priponk v tem delu izvoza.');
    files.forEach(file => {
      const row = el('div', null, 'row'); const text = el('div');
      if (file.status === 'ok') link(text, file.originalName || `Datoteka #${file.id}`, file.path, true); else text.append(el('strong', file.originalName || `Datoteka #${file.id}`));
      text.append(el('p', `${str(file.size)} B · ${file.status === 'ok' ? 'Kopija preverjena' : `Napaka: ${str(file.status)}`}`, 'muted')); raw(text, file, 'Velikost, pot in SHA-256'); row.append(text); parent.append(row);
    });
  }
  function openTask(task) {
    const body = document.getElementById('task-content'); body.replaceChildren(); document.getElementById('task-title').textContent = `#${task.id} · ${task.title}`;
    const project = find('projects', task.project_id); const column = find('columns', task.column_id); const lane = find('swimlanes', task.swimlane_id);
    facts(body, [['Stanje', isOpen(task) ? 'Odprto' : 'Zaključeno'], ['Projekt', project?.name || `#${task.project_id}`], ['Stolpec / steza', `${column?.title || `#${task.column_id}`} / ${lane?.name || `#${task.swimlane_id}`}`], ['Odgovorna oseba', person(task.owner_id)], ['Ustvaril', person(task.creator_id)], ['Rok', readableDate(task.date_due)], ['Ustvarjeno', readableDate(task.date_creation)], ['Zaključeno', readableDate(task.date_completed)], ['Ocenjeni / porabljeni čas', `${str(task.time_estimated)} / ${str(task.time_spent)} h`], ['Score (izvirna vrednost)', task.score]]);
    if (task.description) section(body, 'Opis').append(el('p', task.description, 'prose'));
    const comments = section(body, 'Komentarji'); const commentRows = related('comments', 'task_id', task.id);
    commentRows.forEach(comment => { const row = el('div', null, 'row'); const group = el('div'); group.append(el('strong', `${person(comment.user_id)} · ${readableDate(comment.date_creation)}`), el('p', comment.comment, 'prose')); raw(group, comment); row.append(group); comments.append(row); }); if (!commentRows.length) empty(comments, 'Ni komentarjev.');
    const subtasks = section(body, 'Podopravila in čas'); const items = ordered(related('subtasks', 'task_id', task.id));
    items.forEach(item => { const row = el('div', null, 'row'); const group = el('div'); const status = ['Za opraviti', 'V teku', 'Zaključeno'][Number(item.status)] || 'Neznano stanje'; group.append(el('strong', item.title), el('p', `${status} (${str(item.status)}) · ${person(item.user_id)} · ${str(item.time_spent)} / ${str(item.time_estimated)} h`, 'muted')); raw(group, item); raw(group, related('subtask_time_tracking', 'subtask_id', item.id), 'Evidenca časa'); row.append(group); subtasks.append(row); }); if (!items.length) empty(subtasks, 'Ni podopravil.');
    const tags = section(body, 'Oznake'); const tagRows = related('task_has_tags', 'task_id', task.id); tagRows.forEach(item => tags.append(badge(find('tags', item.tag_id)?.name || `Oznaka #${item.tag_id}`))); if (!tagRows.length) empty(tags, 'Ni oznak.');
    const links = section(body, 'Povezana opravila'); const relationships = rows('task_has_links').filter(item => same(item.task_id, task.id) || same(item.opposite_task_id, task.id));
    relationships.forEach(item => { const otherId = same(item.task_id, task.id) ? item.opposite_task_id : item.task_id; const other = find('tasks', otherId); const row = el('div', null, 'row'); const title = find('links', item.link_id)?.label || find('links', item.link_id)?.name || `Povezava #${item.link_id}`; row.append(el('span', title)); row.append(other ? button(`#${other.id} · ${other.title}`, () => openTask(other), 'link-button') : el('span', `Opravilo #${otherId} ni v izvozu`, 'muted')); links.append(row); }); if (!relationships.length) empty(links, 'Ni povezav.');
    const external = section(body, 'Zunanje povezave'); const externalRows = related('task_has_external_links', 'task_id', task.id);
    externalRows.forEach(item => { const row = el('div', null, 'row'); link(row, item.title || item.url, item.url); raw(row, item); external.append(row); }); if (!externalRows.length) empty(external, 'Ni zunanjih povezav.'); else external.append(el('p', 'Klik na zunanjo povezavo lahko odpre spletno stran. Pregledovalnik jih sam ne nalaga.', 'muted'));
    fileList(section(body, 'Priponke'), (archive.files || []).filter(file => same(file.taskId, task.id)));
    raw(body, related('task_has_metadata', 'task_id', task.id), 'Metapodatki opravila'); raw(body, task);
    const dialog = document.getElementById('task-dialog'); if (!dialog.open) dialog.showModal(); body.scrollTop = 0;
  }
  function renderFinance(project) {
    const metadata = related('project_has_metadata', 'project_id', project.id); const group = section(content, 'Finančni podatki stare aplikacije');
    group.append(el('p', 'Prikaz shranjene tabele, brez izračuna novih projekcij ali prenosa v novi organizator. Score opravil in metapodatki ostanejo v izvirnih zapisih.', 'muted'));
    const get = name => metadata.find(row => row.name === name)?.value;
    let text = get('ui_finance_table_v1');
    if (!text) { empty(group, 'Shranjene finančne tabele ni v izvozu. To ne izključuje finančnih podatkov v opravilih ali drugih metapodatkih.'); raw(group, metadata, 'Vsi projektni metapodatki'); return; }
    try {
      if (str(text).startsWith('@chunked:')) {
        if (!/^@chunked:[1-9]\d*$/.test(str(text))) throw new Error('Neveljavno število delov.');
        const count = Number(str(text).slice(9)); if (!Number.isInteger(count) || count < 1 || count > 100000) throw new Error('Neveljavno število delov.');
        const chunks = Array.from({length: count}, (_, index) => get(`ui_finance_table_v1_chunk_${index}`));
        if (chunks.some(chunk => typeof chunk !== 'string')) throw new Error('Manjka del finančne tabele.'); text = chunks.join('');
      }
      const finance = JSON.parse(text);
      const listKeys = ['contributors', 'months', 'recurringIncomes', 'plannedIncomes', 'recurringExpenses', 'plannedExpenses'];
      const exactInteger = value => Number.isSafeInteger(value) || typeof value === 'string' && /^-?\d+$/.test(value);
      const hasUnsafeInteger = value => typeof value === 'number' ? Number.isInteger(value) && !Number.isSafeInteger(value) : value && typeof value === 'object' ? Object.values(value).some(hasUnsafeInteger) : false;
      if (hasUnsafeInteger(finance)) throw new Error('Tabela vsebuje cela števila zunaj natančnega obsega pregledovalnika. Uporabi ohranjeno izvirno besedilo.');
      if (!finance || finance.schemaVersion !== 1 || typeof finance.currencyCode !== 'string' || !exactInteger(finance.currentBalanceCents) || listKeys.some(key => !Array.isArray(finance[key]) || finance[key].some(item => !item || typeof item !== 'object' || Array.isArray(item)))) throw new Error('Nepodprta ali neveljavna shema finančne tabele.');
      if (finance.months.some(item => !item.incomesByContributorCents || typeof item.incomesByContributorCents !== 'object' || Array.isArray(item.incomesByContributorCents) || Object.values(item.incomesByContributorCents).some(value => !exactInteger(value))) || ['recurringIncomes', 'plannedIncomes', 'recurringExpenses', 'plannedExpenses'].some(key => finance[key].some(item => !exactInteger(item.amountCents)))) throw new Error('Neveljavni ali preveliki denarni zneski.');
      facts(group, [['Valuta (shranjena oznaka)', str(finance.currencyCode)], ['Trenutno stanje (centi)', str(finance.currentBalanceCents)]]);
      const names = new Map((finance.contributors || []).map(item => [str(item.id), item.name]));
      const sections = [['contributors', 'Prispevalci'], ['months', 'Mesečni prihodki'], ['recurringIncomes', 'Ponavljajoči prihodki'], ['plannedIncomes', 'Načrtovani prihodki'], ['recurringExpenses', 'Ponavljajoči stroški'], ['plannedExpenses', 'Načrtovani stroški']];
      sections.forEach(([key, title]) => {
        const items = finance[key]; const target = section(content, title); if (!Array.isArray(items) || !items.length) return empty(target, 'Ni shranjenih vrstic.');
        dataTable(target, items.map(item => ({...item, ...(item.contributorId ? {contributorName: names.get(str(item.contributorId)) || item.contributorId} : {})})));
      }); raw(content, finance, 'Dekodirana izvirna tabela');
    } catch (error) { group.append(el('p', `Tabela ni dekodirana: ${error.message} Izvirni metapodatki so ohranjeni spodaj.`, 'warning')); }
    raw(content, metadata, 'Izvirni projektni metapodatki in deli tabele');
  }
  function dataTable(parent, items) {
    const clean = items.map(sanitize); const keys = [...new Set(clean.flatMap(item => Object.keys(item)))];
    const wrapper = el('div', null, 'scroll-table'); const table = el('table'); const head = el('thead'); const heading = el('tr'); keys.forEach(key => heading.append(el('th', key))); head.append(heading); table.append(head);
    const body = el('tbody'); clean.forEach(item => { const row = el('tr'); keys.forEach(key => row.append(el('td', typeof item[key] === 'object' && item[key] !== null ? JSON.stringify(item[key]) : str(item[key])))); body.append(row); }); table.append(body); wrapper.append(table); parent.append(wrapper);
  }
  function renderTables() {
    content.append(el('h2', 'Izvirne poslovne tabele'), el('p', 'Pregled vsebuje redigiran del arhiva. Varnostna polja, nastavitve in poverilnice niso vključeni. Neznana polja so prikazana kot podatki.', 'muted'));
    const select = el('select'); select.setAttribute('aria-label', 'Tabela'); const names = Object.keys(tables).sort(); if (!names.includes(state.table)) state.table = names[0];
    names.forEach(name => { const option = el('option', `${name} · ${rows(name).length}`); option.value = name; select.append(option); }); select.value = state.table || ''; select.addEventListener('change', () => { state.table = select.value; state.page = 0; render(); }); content.append(select);
    const items = rows(state.table).filter(item => !state.search || JSON.stringify(sanitize(item)).toLocaleLowerCase('sl').includes(state.search));
    if (!items.length) return empty(content, 'Tabela nima zapisov za ta filter.');
    const maxPage = Math.max(0, Math.ceil(items.length / 100) - 1); state.page = Math.min(state.page, maxPage); dataTable(section(content), items.slice(state.page * 100, (state.page + 1) * 100)); pagination(content, items.length, 100, maxPage);
  }
  function renderIntegrity() {
    const integrity = archive.integrity || {}; content.append(el('h2', 'Preverjanje zajema'));
    content.append(el('p', integrity.complete === true ? 'Izvoznik je potrdil preverjanja zajema. Pregledovalnik ne izvaja ponovnega preverjanja celotne varnostne kopije.' : 'Popolnost zajema še ni potrjena. Izvirnega sistema ne upokoji na podlagi tega prikaza.', integrity.complete === true ? 'muted' : 'warning'));
    const problems = [...(integrity.errors || []), ...(integrity.warnings || [])]; const issues = section(content, 'Napake in opozorila'); if (!problems.length) empty(issues, 'Ni zabeleženih napak ali opozoril.');
    problems.forEach(issue => issues.append(el('p', typeof issue === 'string' ? issue : `${str(issue.code)} · ${str(issue.message)}`, 'prose')));
    facts(section(content, 'Datoteke'), Object.entries(integrity.fileCounts || {}).map(([key, value]) => [key, value]));
    const counts = section(content, 'Število zapisov'); dataTable(counts, Object.entries(integrity.tableCounts || {}).map(([table, count]) => ({table, ...count})));
    raw(content, integrity.omittedTables || [], 'Tabele, izključene iz pregledovalnika'); raw(content, integrity.redactedColumns || {}, 'Izključena varnostna polja'); raw(content, archive.source || {}, 'Izvor kopije');
    const missing = (archive.files || []).filter(file => file.status !== 'ok'); if (missing.length) fileList(section(content, 'Priponke z napakami'), missing);
  }
  document.getElementById('search').addEventListener('input', event => { state.search = event.target.value.trim().toLocaleLowerCase('sl'); state.page = 0; render(); });
  document.getElementById('status').addEventListener('change', event => { state.status = event.target.value; state.page = 0; render(); });
  document.getElementById('integrity-button').addEventListener('click', () => { state.view = 'integrity'; state.project = null; render(); });
  document.getElementById('close-dialog').addEventListener('click', () => document.getElementById('task-dialog').close());
  renderCapture(); render();
})();
