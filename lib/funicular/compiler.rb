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
      gather_source_files
      compile_to_mrb
    end

    private

    def check_picorbc_availability!
      unless picorbc_command
        raise PicorbcNotFoundError, <<~ERROR
          picorbc command not found.

          Funicular requires the picorbc mruby compiler (version #{Funicular::PICORBC_VERSION}) to compile Ruby code to .mrb format.

          Please add @picoruby/picorbc to your project dependencies:

          1. Add to package.json:
             npm install --save-dev @picoruby/picorbc@#{Funicular::PICORBC_VERSION}

          2. Or if you don't have package.json yet:
             npm init -y
             npm install --save-dev @picoruby/picorbc@#{Funicular::PICORBC_VERSION}

          For more information: https://www.npmjs.com/package/@picoruby/picorbc
        ERROR
      end

      check_picorbc_version!
    end

    def picorbc_command
      @picorbc_command ||= find_picorbc_command
    end

    def find_picorbc_command
      # Try local node_modules first (project dependency - recommended)
      local_picorbc = Rails.root.join("node_modules", ".bin", "picorbc")
      return local_picorbc.to_s if File.executable?(local_picorbc)

      # Check if global picorbc exists and warn
      if system("which picorbc > /dev/null 2>&1")
        warn_global_picorbc
        return "picorbc"
      end

      # Not found
      nil
    end

    def warn_global_picorbc
      logger&.warn("Using global picorbc. Consider adding @picoruby/picorbc@#{Funicular::PICORBC_VERSION} to package.json for version consistency.")
      puts "WARNING: Using global picorbc. Consider adding @picoruby/picorbc@#{Funicular::PICORBC_VERSION} to package.json for version consistency." if debug_mode
    end

    def check_picorbc_version!
      version_output = `#{picorbc_command} --version 2>&1`.strip
      actual_version = version_output.match(/(\d+\.\d+\.\d+)/)?.[1]

      unless actual_version
        log "Warning: Could not detect picorbc version"
        return
      end

      if actual_version != Funicular::PICORBC_VERSION
        warn_version_mismatch(actual_version)
      end
    end

    def warn_version_mismatch(actual_version)
      message = "picorbc version mismatch: expected #{Funicular::PICORBC_VERSION}, found #{actual_version}. Please install @picoruby/picorbc@#{Funicular::PICORBC_VERSION}"
      logger&.warn(message)
      puts "WARNING: #{message}" if debug_mode
    end

    def gather_source_files
      models_files = Dir.glob(File.join(source_dir, "models", "**", "*.rb")).sort
      components_files = Dir.glob(File.join(source_dir, "components", "**", "*.rb")).sort
      initializer_files = Dir.glob(File.join(source_dir, "*_initializer.rb")).sort +
                          Dir.glob(File.join(source_dir, "initializer.rb")).sort

      # Order: models -> components -> initializer
      all_files = models_files + components_files + initializer_files

      if all_files.empty?
        raise "No Ruby files found in #{source_dir}"
      end

      # Create a small temp file for ENV setting
      env_file = "#{output_file}.env.rb"
      File.open(env_file, "w") do |f|
        f.puts "ENV['FUNICULAR_ENV'] = '#{Rails.env}'"
      end

      @source_files = all_files
      @env_file = env_file
    end

    def log(message)
      if logger
        logger.info(message)
        # Also output to stdout so logs are visible in terminal during development
        puts message if debug_mode
      else
        puts message
      end
    end

    def compile_to_mrb
      output_dir = File.dirname(output_file)
      FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

      compile_options = debug_mode ? "-g" : ""
      # Pass all source files directly to picorbc, maintaining order
      all_files = @source_files + [@env_file]
      files_list = all_files.join(" ")
      command = "picorbc #{compile_options} -o #{output_file} #{files_list}"

      log "Compiling Funicular application..."
      log "  Source: #{source_dir}"
      log "  Input files:"
      all_files.each do |file|
        log "    - #{file}"
      end
      log "  Output: #{output_file}"
      log "  Debug mode: #{debug_mode}"
      log "  Files: #{all_files.size} files"

      result = system(command)

      unless result
        raise "Failed to compile with picorbc. Command: #{command}"
      end

      log "Successfully compiled to #{output_file}"
    ensure
      # Keep temp file for debugging - set FUNICULAR_KEEP_TEMP=1 to inspect temp file
      unless ENV['FUNICULAR_KEEP_TEMP']
        File.delete(@env_file) if @env_file && File.exist?(@env_file)
      end
    end
  end
end
