## [0.1.0] - 2026-04-20

### Added

- Consolidated with picoruby-funicular: merged the full PicoRuby frontend
  framework into this gem, including Component, Cable, VDOM, Router,
  FormBuilder, Model, HTTP, FileUpload, ErrorBoundary, Styles, Differ,
  Patcher, Debug, and EnvironmentInquirer, along with RBS signatures and
  comprehensive test suite
- Bundle PicoRuby.wasm and picorbc WASM artifacts into the gem via a
  `rake copy_wasm` task; artifacts are vendored at build time so no
  runtime npm lookup is required
- `Funicular::Configuration` with per-environment PicoRuby.wasm source
  selection (`:local_debug`, `:local_dist`, `:cdn`) and optional
  `cdn_version` override
- `picoruby_include_tag` view helper (auto-registered via Railtie) that
  serves the appropriate PicoRuby.wasm build per environment
- `funicular:install:wasm` rake sub-task to copy dist/debug WASM builds
  into `public/picoruby/`
- Rails Asset Pipeline integration: Rack middleware, compiler, and
  `funicular:compile` / `funicular:install` rake tasks
- `funicular routes` CLI command and `Funicular::RouteParser` to inspect
  Rails routes from the command line
- Component Debug Highlighter: CSS/JS assets (`funicular_debug.css`,
  `funicular_debug.js`) that highlight the selected component in the
  browser
- `ENV['FUNICULAR_ENV']` is now set from `Rails.env` in generated
  `application.rb`

### Changed

- picorbc is now resolved from a vendored WASM artifact; removed
  npm-based picorbc lookup and all `PICORBC_VERSION` environment variable
  logic
- Upgraded picorbc to the latest version
- Switched test framework from test/unit to minitest

### Fixed

- Asset pipeline: middleware now detects whether `app.mrb` has actually
  changed before recompiling, preventing unnecessary rebuilds
- XSS vulnerabilities in VDOM attribute handling: expanded
  `URL_ATTRIBUTES` constant, applied case-insensitive `javascript:` URI
  blocking, and added the same URL validation to `Patcher#update_props`
  and `Patcher#create_element`
- XSS vulnerability in Debug module: replaced manual JSON string
  concatenation with `JSON.generate` to eliminate escaping gaps
- `funicular:compile` rake task
- `funicular:install` rake task
- Rack middleware
- RBS type signatures

### Removed

- Debugger Chrome extension (`debugger/` directory)
- `.ruby-version` file

## [0.0.1] - 2025-11-27

- Initial release
