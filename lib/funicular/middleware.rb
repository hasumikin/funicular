# frozen_string_literal: true

module Funicular
  class Middleware
    def initialize(app)
      @app = app
      @source_dir = Rails.root.join("app", "funicular")
      @output_file = Rails.root.join("app", "assets", "builds", "app.mrb")
      @last_mtime = nil
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

      if @last_mtime.nil? || current_mtime > @last_mtime
        begin
          Rails.logger.info "Funicular: Source files changed, recompiling..."
          compiler = Compiler.new(
            source_dir: @source_dir,
            output_file: @output_file,
            debug_mode: true,
            logger: Rails.logger
          )
          compiler.compile
          @last_mtime = current_mtime
        rescue => e
          Rails.logger.error "Funicular compilation failed: #{e.message}"
        end
      end
    end

    def latest_source_mtime
      source_files = Dir.glob(File.join(@source_dir, "**", "*.rb"))
      return Time.at(0) if source_files.empty?

      source_files.map { |f| File.mtime(f) }.max
    end
  end
end
