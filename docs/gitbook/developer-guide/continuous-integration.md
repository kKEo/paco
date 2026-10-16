---
description: The GitHub Actions workflows, what they check, how the docs site is published, and how to cut a release.
---

# Continuous integration

Four workflows live in `.github/workflows/`. Dependabot (`.github/dependabot.yml`) keeps the actions and the docs site's npm packages up to date.

| Workflow | Runs on | Trigger | What it does |
|---|---|---|---|
| **CI** (`ci.yml`) | `macos-15` | Push to `master`, pull requests, manual | Checks the Xcode project is in sync, builds Debug, runs the tests, builds Release |
| **Docs** (`docs.yml`) | `ubuntu-latest` | Changes under `docs/` | Checks the book's links, table of contents, images and diagrams |
| **Pages** (`pages.yml`) | `ubuntu-latest` | Changes under `docs/` | Builds the book into a static site; deploys it to GitHub Pages from `master` |
| **Release** (`release.yml`) | `macos-15` | Tag `v*`, manual | Builds a signed pkg, notarizes it, publishes a GitHub Release |

CI skips commits that only touch documentation, and Docs runs only for them, so each kind of change pays only for its own checks.

## CI

1. **Project sync.** Installs XcodeGen at the pinned `XCODEGEN_VERSION`, runs `xcodegen generate`, and fails if `PaCo.xcodeproj` changed. Bump the pin when you upgrade XcodeGen locally, since versions generate slightly different files.
2. **Build (Debug)** of the `PaCo` scheme, which builds all four targets.
3. **Test** the `PaCoTests` scheme. On failure, the `.xcresult` bundle is uploaded as an artifact for seven days.
4. **Build (Release)**, which compiles without `DEBUG` and so catches code that only builds under `#if DEBUG`.

Builds are ad-hoc signed (`CODE_SIGN_IDENTITY=-`). That is enough to compile and to run the unit tests, which link only PaCoShared. Nothing in CI runs the daemon, which would refuse ad-hoc signed peers anyway.

To reproduce CI locally:

```bash
xcodegen generate && git diff --exit-code PaCo.xcodeproj
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests -configuration Debug \
  -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```

## Docs

`python3 .github/scripts/check_book.py` runs the same checks locally:

* every relative link resolves, and every `#anchor` matches a heading in the target page;
* every page is in `SUMMARY.md`, and every entry in it exists;
* every image resolves, every SVG in `.gitbook/assets/` is used and is well-formed;
* `docs/diagrams/ug.py` and `dg.py` reproduce the committed SVGs byte for byte.

When the last check fails, regenerate the diagrams and commit them:

```bash
python3 docs/diagrams/ug.py docs/gitbook/.gitbook/assets
python3 docs/diagrams/dg.py docs/gitbook/.gitbook/assets
```

## Pages

The book is published at [kkeo.github.io/paco](https://kkeo.github.io/paco/). The source stays in GitBook format in `docs/gitbook/`; `docs/site/` turns it into a static site with [HonKit](https://github.com/honkit/honkit), the maintained fork of the original GitBook tool.

| File | Role |
|---|---|
| `docs/site/package.json`, `package-lock.json` | Pinned HonKit and plugins |
| `docs/site/book.json` | Site title and plugins: `hints` for the callout blocks, and the local `paco` plugin |
| `docs/site/plugin/` | Local plugin: renders Mermaid diagrams in the browser with a pinned Mermaid version, styles the sidebar, figures and top bar, adds a GitHub link |
| `docs/site/theme/_layouts/website/summary.html` | Replaces the theme's sidebar: logo, search, one collapsible group per `SUMMARY.md` part, footer |
| `docs/site/build.sh` | Copies the book and the theme overrides, moves `.gitbook/assets` to `assets/` (static hosts skip dot-folders), runs HonKit, adds `.nojekyll` |
| `docs/site/check_site.py` | Fails on broken links, anchors or images in the HTML, `.md` links, unrendered callouts or tables, and pages without the custom sidebar |

Pull requests that touch `docs/` build and check the site without deploying. Pushes to `master` also deploy it. Pages must use **GitHub Actions** as its source (*Settings → Pages*), which is already the case for this repository.

To preview locally:

```bash
cd docs/site && npm ci && ./build.sh
python3 check_site.py ../../build/site
python3 -m http.server --directory ../../build/site 8000   # then open http://localhost:8000
```

{% hint style="info" %}
HonKit's Markdown parser is stricter than GitBook's. It does not support a table nested inside a list item (end the list first and put the table after it) or a backslash at the end of a line as a line break (it prints the backslash). `check_site.py` catches raw table syntax in the output, and `check_book.py` rejects backslash line breaks.
{% endhint %}

The sidebar has one collapsible group per titled part of `SUMMARY.md`. The group holding the current page is always open; the others remember what the reader last chose. Press <kbd>/</kbd> to jump to the search box. Template comments in `theme/_layouts` use HonKit's triple-hash comment delimiters (see the top of `summary.html`), not the usual Nunjucks ones.

## Release

### One-time setup

Create these under **Settings → Secrets and variables → Actions**, either at repository level or in an environment named `release`. The workflow uses that environment, so you can add required reviewers to it.

| Kind | Name | Value |
|---|---|---|
| Variable | `TEAM_ID` | Your 10-character Apple Developer Team ID |
| Secret | `DEVELOPER_ID_APPLICATION_P12` | Base64 of the exported *Developer ID Application* certificate and key |
| Secret | `DEVELOPER_ID_INSTALLER_P12` | Base64 of the exported *Developer ID Installer* certificate and key |
| Secret | `CERTIFICATES_P12_PASSWORD` | The password used when exporting both `.p12` files |
| Secret | `NOTARY_APPLE_ID` | Apple ID used to notarize |
| Secret | `NOTARY_APP_PASSWORD` | An app-specific password for that Apple ID |

Export each certificate from Keychain Access as a `.p12`, then:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

### Cutting a release

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow imports the certificates into a temporary keychain, runs `make notarize` with `TEAM_ID` and the version taken from the tag, verifies the signature and the stapled ticket, and publishes `PaCo-1.2.0.pkg` with a SHA-256 checksum as a GitHub Release with generated notes. The temporary keychain is deleted at the end, even on failure.

Running the workflow manually builds the pkg for a version you enter, optionally notarizes it, and uploads it as a workflow artifact without creating a release.

{% hint style="warning" %}
Until the packaging issue in [Known limitations](known-limitations.md#packaging) is fixed, notarization is expected to fail: `make pkg` copies the daemon and agent into the already-signed app bundle. Fix the Makefile first, then use the workflow.
{% endhint %}
