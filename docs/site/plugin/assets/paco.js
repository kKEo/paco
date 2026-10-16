/* global require, document, window */
// Mermaid is loaded from a pinned CDN version on first use and re-run after every
// client-side page change (HonKit swaps page content without a full reload).
// The sidebar (theme/_layouts/website/summary.html) is re-rendered on every page
// change too, so its state is re-applied in onPageChange.
(function () {
  var MERMAID_URL = 'https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js';
  var GROUPS_KEY = 'paco:sidebar-groups';
  var GITHUB_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21"/></svg>';
  var loading = null;
  var applyingGroups = false;

  function loadMermaid() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (loading) return loading;
    loading = new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = MERMAID_URL;
      s.onload = function () {
        window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'neutral' });
        resolve(window.mermaid);
      };
      s.onerror = reject;
      document.head.appendChild(s);
    });
    return loading;
  }

  function renderMermaid() {
    var blocks = document.querySelectorAll('pre.mermaid-src');
    if (!blocks.length) return;
    var nodes = [];
    blocks.forEach(function (pre) {
      var div = document.createElement('div');
      div.className = 'mermaid';
      div.textContent = pre.textContent;
      pre.replaceWith(div);
      nodes.push(div);
    });
    loadMermaid().then(function (m) { m.run({ nodes: nodes }); }).catch(function () {
      nodes.forEach(function (n) { n.classList.add('mermaid-failed'); });
    });
  }

  function addRepoLink() {
    var cfg = document.getElementById('paco-config');
    var header = document.querySelector('.book-header');
    if (!cfg || !header || header.querySelector('.paco-repo')) return;
    var a = document.createElement('a');
    a.className = 'btn pull-right paco-repo';
    a.href = cfg.getAttribute('data-repository');
    a.target = '_blank';
    a.rel = 'noopener';
    a.innerHTML = GITHUB_ICON + '<span>GitHub</span>';
    a.setAttribute('aria-label', 'View PaCo on GitHub');
    header.appendChild(a);
  }

  // Sidebar groups: the one holding the current page is always open (rendered so
  // by the template); the others keep whatever the reader last chose.
  function readGroups() {
    try { return JSON.parse(window.localStorage.getItem(GROUPS_KEY)) || {}; } catch (e) { return {}; }
  }

  function writeGroups(state) {
    try { window.localStorage.setItem(GROUPS_KEY, JSON.stringify(state)); } catch (e) { /* private mode */ }
  }

  function applyGroups() {
    var state = readGroups();
    applyingGroups = true;
    document.querySelectorAll('.book-summary details[data-group]').forEach(function (d) {
      if (d.querySelector('li.chapter.active')) {
        d.open = true;
      } else if (Object.prototype.hasOwnProperty.call(state, d.dataset.group)) {
        d.open = state[d.dataset.group];
      }
    });
    // 'toggle' events are queued; ignore the ones caused by this function.
    window.setTimeout(function () { applyingGroups = false; }, 0);
  }

  document.addEventListener('toggle', function (e) {
    var d = e.target;
    if (applyingGroups || !d.matches || !d.matches('.book-summary details[data-group]')) return;
    var state = readGroups();
    state[d.dataset.group] = d.open;
    writeGroups(state);
  }, true);

  // Keep the current page visible in the sidebar (below the sticky search box).
  function revealActive() {
    var summary = document.querySelector('.book-summary');
    var active = summary && summary.querySelector('li.chapter.active > a');
    if (!active) return;
    var search = document.getElementById('book-search-input');
    var top = search ? search.getBoundingClientRect().bottom : summary.getBoundingClientRect().top;
    var bottom = summary.getBoundingClientRect().bottom;
    var r = active.getBoundingClientRect();
    if (r.top < top || r.bottom > bottom) {
      summary.scrollTop += r.top - top - (bottom - top) / 3;
    }
  }

  // "/" focuses the search box, Escape leaves it.
  document.addEventListener('keydown', function (e) {
    var input = document.querySelector('#book-search-input input');
    if (!input) return;
    var t = e.target;
    var typing = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    if (e.key === '/' && !typing && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      input.focus();
    } else if (e.key === 'Escape' && t === input) {
      input.blur();
    }
  });
  document.addEventListener('focusin', function (e) {
    if (e.target.closest && e.target.closest('#book-search-input')) {
      document.getElementById('book-search-input').classList.add('paco-has-focus');
    }
  });
  document.addEventListener('focusout', function (e) {
    var box = e.target.closest && e.target.closest('#book-search-input');
    if (box && !e.target.value) box.classList.remove('paco-has-focus');
  });

  function onPageChange() {
    renderMermaid();
    addRepoLink();
    applyGroups();
    revealActive();
  }

  require(['gitbook'], function (gitbook) {
    gitbook.events.bind('page.change', onPageChange);
  });
})();
