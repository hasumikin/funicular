# frozen_string_literal: true

module Funicular
  class Middleware
    class << self
      attr_accessor :last_mtime, :compiling, :mutex

      def reset!
        @last_mtime = nil
        @compiling = false
        @mutex = Mutex.new
      end
    end

    # Initialize class state
    reset!

    def initialize(app)
      @app = app
      @source_dir = Rails.root.join("app", "funicular")
      @output_file = Rails.root.join("app", "assets", "builds", "app.mrb")
    end

    def call(env)
      recompile_if_needed if should_check_recompile?
      @app.call(env)
    end

    private

    def should_check_recompile?
      Rails.env.development? && Dir.exist?(@source_dir)
    end

    def recompile_if_needed
      current_mtime = latest_source_mtime

      # Skip if already compiling or if no changes detected
      return if self.class.compiling
      return if self.class.last_mtime && current_mtime <= self.class.last_mtime

      self.class.mutex.synchronize do
        # Double-check inside the lock
        return if self.class.compiling
        return if self.class.last_mtime && current_mtime <= self.class.last_mtime

        self.class.compiling = true
      end

      begin
        Rails.logger.info "Funicular: Source files changed, recompiling..."
        compiler = Compiler.new(
          source_dir: @source_dir,
          output_file: @output_file,
          debug_mode: true,
          logger: Rails.logger
        )
        compiler.compile
        self.class.last_mtime = current_mtime
      rescue => e
        Rails.logger.error "Funicular compilation failed: #{e.message}"
      ensure
        self.class.compiling = false
      end
    end

    def latest_source_mtime
      source_files = Dir.glob(File.join(@source_dir, "**", "*.rb"))
      return Time.at(0) if source_files.empty?

      source_files.map { |f| File.mtime(f) }.max
    end
  end
end
