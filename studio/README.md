# tex_math_studio

macOS Flutter three-way comparison workbench inspecting **`tex_math`**, **MathJax `4.1.3`**, and **KaTeX `0.19.1`** side by side (`Side-by-Side`, `Pixel Diff`, and `Curtain Diff`) alongside `DisplayMetrics`, SVG, Presentation MathML, and spoken-text exports.

## Highlights

* **Tokenized Loopback Web Harnesses**: Serves local MathJax `4.1.3` (`ui/safe` + `safeOptions` + package allowlist) and KaTeX `0.19.1` (`trust: false`) assets from `tool/oracle/node_modules/` over a per-session tokenized `127.0.0.1` HTTP server with `Host` validation, CSP headers, symlink-safe path checks, and strict `WKWebView` navigation locking.
* **Async Corpus & Isolate Diffing**: Loads the 352-case corpus off the UI thread (`StudioCorpusLoader.loadAsync`), shares one memoized `DisplayList` between preview and inspector (`TexMath.displayList`), computes RGBA diffs in `Isolate.run`, and automatically invalidates stale captures when inputs or targets change.

## Setup, Tests & Launch

Resolve workspace dependencies and oracle JS assets at the repository root, then test or launch on macOS (`studio/macos/`):

```bash
flutter pub get
(cd tool/oracle && npm ci)
(cd studio && flutter test)
(cd studio && flutter run -d macos)
```

For architecture, diff-mode controls, and headless CLI oracle usage, see the [Comparison Studio Guide](../doc/STUDIO_GUIDE.md).
