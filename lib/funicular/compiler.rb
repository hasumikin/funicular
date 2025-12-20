# frozen_string_literal: true

module Funicular
  class Compiler
    class PicorbcNotFoundError < StandardError; end

    attr_reader :source_dir, :output_file, :debug_mode, :logger

    def initialize(source_dir:, output_file:, debug_mode: false, logger: nil)
      @source_dir = source_dir
      @output_file = output_file
      @debug_mode = debug_mode
      @logger = logger
    end

    def compile
      check_picorbc_availability!
      concatenate_source_files
      compile_to_mrb
    end

    private

    def check_picorbc_availability!
      result = system("which picorbc > /dev/null 2>&1")
      unless result
        raise PicorbcNotFoundError, <<~ERROR
          picorbc command not found in PATH.

          Funicular requires the picorbc mruby compiler to compile Ruby code to .mrb format.
          Please ensure that picorbc is installed and available in your PATH.

          Installation instructions:
          - Install picoruby: https://github.com/picoruby/picoruby
          - Or add picorbc to your PATH
        ERROR
      end
    end

    def concatenate_source_files
      models_files = Dir.glob(File.join(source_dir, "models", "**", "*.rb")).sort
      components_files = Dir.glob(File.join(source_dir, "components", "**", "*.rb")).sort
      initializer_files = Dir.glob(File.join(source_dir, "*_initializer.rb")).sort +
                          Dir.glob(File.join(source_dir, "initializer.rb")).sort

      # Order: models -> components -> initializer
      all_files = models_files + components_files + initializer_files

      if all_files.empty?
        raise "No Ruby files found in #{source_dir}"
      end

      temp_file = "#{output_file}.tmp.rb"
      File.open(temp_file, "w") do |f|
        all_files.each do |file|
          f.puts "# Source: #{file}"
          f.puts File.read(file)
          f.puts
        end
        f.puts "ENV['FUNICULAR_ENV'] = '#{Rails.env}'"
      end

      @temp_source_file = temp_file
    end

    def log(message)
      if logger
        logger.info(message)
      else
        puts message
      end
    end

    def compile_to_mrb
      output_dir = File.dirname(output_file)
      FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

      compile_options = debug_mode ? "-g" : ""
      command = "picorbc #{compile_options} -o #{output_file} #{@temp_source_file}"

      log "Compiling Funicular application..."
      log "  Source: #{source_dir}"
      log "  Output: #{output_file}"
      log "  Debug mode: #{debug_mode}"
      log "  Temp source: #{@temp_source_file}"

      result = system(command)

      unless result
        raise "Failed to compile with picorbc. Command: #{command}"
      end

      log "Successfully compiled to #{output_file}"
    ensure
      # Keep temp file for debugging - set FUNICULAR_KEEP_TEMP=1 to inspect temp file
      unless ENV['FUNICULAR_KEEP_TEMP']
        File.delete(@temp_source_file) if @temp_source_file && File.exist?(@temp_source_file)
      end
    end
  end
end
