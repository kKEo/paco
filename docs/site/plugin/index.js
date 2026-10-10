// Local HonKit plugin for the PaCo docs site.
// - Turns ```mermaid fences into <pre class="mermaid-src"> blocks before Markdown
//   rendering (the highlighter has no Mermaid grammar), which paco.js renders in the
//   browser with a pinned Mermaid version.
// - Passes the repository URL to the client for a "GitHub" header link.
const escapeHTML = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

module.exports = {
  website: {
    assets: './assets',
    js: ['paco.js'],
    css: ['paco.css'],
  },
  hooks: {
    'page:before': function (page) {
      const repo = (this.config.get('pluginsConfig.paco') || {}).repository || '';
      const content = page.content.replace(/^```mermaid[ \t]*\n([\s\S]*?)^```[ \t]*$/gm,
        (_, body) => `<pre class="mermaid-src">${escapeHTML(body.replace(/\n$/, ''))}</pre>`);
      page.content = `<span id="paco-config" data-repository="${escapeHTML(repo)}" hidden></span>\n\n${content}`;
      return page;
    },
  },
};
