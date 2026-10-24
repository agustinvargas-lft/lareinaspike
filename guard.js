// Whitelist guard injected into the page before exploring the checkout.
// Only XHR/fetch to ALLOWED paths may leave the page; everything else is
// rejected and recorded in window.__blocked so we can see what the site tried.
// Page navigations are blocked separately with:
//   agent-browser network route '*' --abort --resource-type document
// The allowlist lives in window.__allow (regex sources) so it can be extended at runtime.
(() => {
  window.__allow ||= ['^/?TicketVal\\.asp$'];
  const ALLOWED = { some: (fn) => window.__allow.some((src) => fn(new RegExp(src, 'i'))) };
  const blocked = (window.__blocked = []);
  const allowed = (window.__allowed = []);
  const pathOf = (u) => {
    try { const x = new URL(u, location.href); return x.host === location.host ? x.pathname + x.search : x.href; }
    catch { return String(u); }
  };
  const ok = (u) => ALLOWED.some((re) => re.test(pathOf(u)));

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    if (!ok(url)) { blocked.push(`XHR ${method} ${pathOf(url)}`); throw new Error(`guard: blocked ${url}`); }
    allowed.push(`XHR ${method} ${pathOf(url)}`);
    return open.apply(this, arguments);
  };

  const fetch_ = window.fetch;
  window.fetch = function (url, opts) {
    const u = typeof url === 'string' ? url : url.url;
    if (!ok(u)) { blocked.push(`fetch ${pathOf(u)}`); return Promise.reject(new Error(`guard: blocked ${u}`)); }
    allowed.push(`fetch ${pathOf(u)}`);
    return fetch_.apply(this, arguments);
  };

  navigator.sendBeacon = (u) => { blocked.push(`beacon ${pathOf(u)}`); return false; };
  HTMLFormElement.prototype.submit = function () { blocked.push(`form.submit ${this.action}`); };
  document.addEventListener('submit', (e) => { e.preventDefault(); e.stopImmediatePropagation(); blocked.push(`submit ${e.target.action}`); }, true);
  return 'guard installed';
})();
