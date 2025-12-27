# frozen_string_literal: true

# Exclude app/funicular from autoloading (PicoRuby.wasm code, not for CRuby)
Rails.autoloaders.main.ignore(Rails.root.join("app/funicular"))
