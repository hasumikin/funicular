# frozen_string_literal: true

require_relative "funicular/version"
require_relative "funicular/compiler"

if defined?(Rails)
  require_relative "funicular/middleware"
  require_relative "funicular/railtie"
end

module Funicular
  class Error < StandardError; end
end
