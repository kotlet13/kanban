/* No network requests or credentials. Build an explicit link to the user's host. */
'use strict';
const form = document.querySelector('[data-server-form]');
if (form) {
  const input = form.querySelector('input');
  const error = form.querySelector('[data-error]');
  const result = form.querySelector('[data-result]');
  const link = form.querySelector('[data-server-link]');
  const host = form.querySelector('[data-host]');
  const reset = () => { result.hidden = true; link.removeAttribute('href'); error.textContent = ''; };
  input.addEventListener('input', reset);
  form.addEventListener('submit', (event) => {
    event.preventDefault(); reset();
    const raw = input.value.trim();
    try {
      if (!/^https:\/\//i.test(raw) || /[\s\\]/.test(raw)) throw new Error('invalid');
      const base = new URL(raw);
      if (base.protocol !== 'https:' || !base.hostname || base.username || base.password || base.search || base.hash) throw new Error('invalid');
      const path = base.pathname.replace(/\/+$/, '');
      // A base directory is expected; do not turn an index.php URL into a subdirectory.
      if (/\.php$/i.test(path)) throw new Error('invalid');
      base.pathname = `${path}/index.php`;
      base.search = new URLSearchParams({controller:'AccountDeletionController',action:'index',plugin:'FamilyHub'}).toString();
      link.href = base.href;
      host.textContent = `${base.origin}${path}/`;
      result.hidden = false;
      link.focus();
    } catch (_) {
      error.textContent = form.dataset.errorMessage;
      input.focus();
    }
  });
}
