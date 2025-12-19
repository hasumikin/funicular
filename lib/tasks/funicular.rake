# frozen_string_literal: true

namespace :funicular do
  desc "Compile Funicular Ruby files to .mrb format"
  task compile: :environment do
    require "funicular/compiler"

    source_dir = Rails.root.join("app", "funicular")
    output_file = Rails.root.join("app", "assets", "builds", "application.mrb")
    debug_mode = !Rails.env.production?

    unless Dir.exist?(source_dir)
      puts "Skipping Funicular compilation: #{source_dir} does not exist"
      next
    end

    begin
      compiler = Funicular::Compiler.new(
        source_dir: source_dir,
        output_file: output_file,
        debug_mode: debug_mode
      )
      compiler.compile
    rescue Funicular::Compiler::PicorbcNotFoundError => e
      puts "ERROR: #{e.message}"
      exit 1
    rescue => e
      puts "ERROR: Failed to compile Funicular application"
      puts e.message
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc "Show all Funicular routes"
  task routes: :environment do
    require "funicular/commands/routes"

    begin
      Funicular::Commands::Routes.new.execute
    rescue => e
      puts "ERROR: Failed to display routes"
      puts e.message
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end

# Hook into assets:precompile for production deployment
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["funicular:compile"])
end
