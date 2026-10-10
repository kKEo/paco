/* global require, document, window */
// Mermaid is loaded from a pinned CDN version on first use and re-run after every
// client-side page change (HonKit swaps page content without a full reload).
(function () {
  var MERMAID_URL = 'https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js';
  var loading = null;

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
    a.textContent = 'GitHub';
    a.setAttribute('aria-label', 'View PaCo on GitHub');
    header.appendChild(a);
  }

  require(['gitbook'], function (gitbook) {
    gitbook.events.bind('page.change', function () {
      renderMermaid();
      addRepoLink();
    });
  });
})();
