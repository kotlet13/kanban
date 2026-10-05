// Entirely synthetic. Never copied into a real archive by the exporter.
const finance = {
  schemaVersion: 1, currencyCode: 'EUR', currentBalanceCents: -12345,
  contributors: [{id: 'member', name: 'Testna oseba'}],
  months: [{monthKey: '2026-10', incomesByContributorCents: {member: 56789}}],
  recurringIncomes: [], plannedIncomes: [],
  recurringExpenses: [{id: 'r1', category: 'Testni strošek', amountCents: 2500, startMonthKey: '2026-10', enabled: false}],
  plannedExpenses: [], unknownBusinessField: 'Ohranjeno'
};
module.exports = {
  schemaVersion: 1, generatedAt: '2026-10-04T10:00:00Z',
  source: {kanboardVersion: '1.2.54', capturedAt: '2026-10-04T09:00:00Z'},
  tables: {
    projects: [{id: 1, name: 'Testni dom', is_active: 1, description: 'Sintetični projekt'}, {id: 2, name: 'Arhiviran test', is_active: 0}],
    columns: [{id: 10, project_id: 1, title: 'Načrt', position: 1}],
    swimlanes: [{id: 20, project_id: 1, name: 'Privzeta steza', position: 1}],
    tasks: [{id: 100, project_id: 1, column_id: 10, swimlane_id: 20, title: '<img src=https://example.invalid/x onerror=alert(1)>', description: 'Besedilo **brez izvajanja HTML**', is_active: 1, owner_id: 3, creator_id: 3, position: 1, score: 150, date_due: 1791110400}, {id: 101, project_id: 2, title: 'Zaključeno testno opravilo', is_active: 0}],
    users: [{id: 3, username: 'test', name: 'Testna oseba', password: 'SECRET-HASH', api_token: 'SECRET-TOKEN'}],
    comments: [{id: 1, task_id: 100, user_id: 3, comment: '<script>not executed</script>', date_creation: 1791110400}],
    subtasks: [{id: 50, task_id: 100, title: 'Evidenca ur', status: 2, time_spent: 1.25}],
    subtask_time_tracking: [{id: 1, subtask_id: 50, user_id: 3, time_spent: 1.25}],
    tags: [{id: 6, name: 'Nakup'}], task_has_tags: [{task_id: 100, tag_id: 6}],
    task_has_links: [{task_id: 100, opposite_task_id: 101, link_id: 7}], links: [{id: 7, label: 'Povezano z'}],
    task_has_external_links: [{id: 1, task_id: 100, title: 'Varna spletna povezava', url: 'https://example.invalid/test'}, {id: 2, task_id: 100, title: 'Nevarna povezava', url: 'javascript:alert(1)'}],
    project_has_metadata: [{project_id: 1, name: 'ui_finance_table_v1', value: JSON.stringify(finance)}, {project_id: 1, name: 'api_key', value: 'SECRET-METADATA'}],
    settings: [{name: 'secret', value: 'SECRET-SETTINGS'}]
  },
  files: [{table: 'task_has_files', id: 1, taskId: 100, originalName: 'test.txt', path: 'attachments/task_has_files/1-test.txt', status: 'ok', size: 5, sha256: 'synthetic'}, {table: 'task_has_files', id: 2, taskId: 100, originalName: 'missing.txt', path: null, status: 'missing'}],
  integrity: {complete: false, errors: [{code: 'missing_file', message: 'Sintetična manjkajoča priponka.'}], warnings: [], tableCounts: {tasks: {source: 2, privateExport: 2, browseExport: 2}}, fileCounts: {referenced: 2, copied: 1, missing: 1}, omittedTables: ['settings'], redactedColumns: {users: ['password', 'api_token']}}
};
