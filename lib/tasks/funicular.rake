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

  desc "Install Funicular debug assets for development"
  task :install do
    require "fileutils"

    javascripts_dir = Rails.root.join("app", "assets", "javascripts")
    stylesheets_dir = Rails.root.join("app", "assets", "stylesheets")
    initializers_dir = Rails.root.join("config", "initializers")

    FileUtils.mkdir_p(javascripts_dir)
    FileUtils.mkdir_p(stylesheets_dir)
    FileUtils.mkdir_p(initializers_dir)

    source_js = File.expand_path("../funicular/assets/funicular_debug.js", __dir__)
    source_css = File.expand_path("../funicular/assets/funicular_debug.css", __dir__)
    source_initializer = File.expand_path("../funicular/assets/funicular.rb", __dir__)

    dest_js = javascripts_dir.join("funicular_debug.js")
    dest_css = stylesheets_dir.join("funicular_debug.css")
    dest_initializer = initializers_dir.join("funicular.rb")

    FileUtils.cp(source_js, dest_js)
    FileUtils.cp(source_css, dest_css)
    FileUtils.cp(source_initializer, dest_initializer)

    puts "✅ Funicular debug assets installed!"
    puts "   - #{dest_js}"
    puts "   - #{dest_css}"
    puts "   - #{dest_initializer}"
    puts ""
    puts "📝 Next steps:"
    puts "   Add to your layout (development only):"
    puts '   <% if Rails.env.development? %>'
    puts '     <%= javascript_include_tag "funicular_debug", "data-turbo-track": "reload" %>'
    puts '     <%= stylesheet_link_tag "funicular_debug", "data-turbo-track": "reload" %>'
    puts '   <% end %>'
  end
end

# Hook into assets:precompile for production deployment
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["funicular:compile"])
end
