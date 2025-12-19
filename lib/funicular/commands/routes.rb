# frozen_string_literal: true

require_relative "../route_parser"

module Funicular
  module Commands
    class Routes
      def execute
        # Check if we're in a Rails app
        unless File.exist?("config/application.rb")
          puts "Error: Not in a Rails application directory"
          exit 1
        end

        # Load Rails environment if not already loaded (CLI usage)
        unless defined?(Rails)
          require "./config/environment"
        end

        source_dir = Rails.root.join("app", "funicular")
        initializer_file = source_dir.join("initializer.rb")

        unless File.exist?(initializer_file)
          puts "No Funicular routes found (#{initializer_file} does not exist)"
          exit 0
        end

        parser = RouteParser.new(initializer_file)
        routes = parser.parse

        if routes.empty?
          puts "No routes defined"
          exit 0
        end

        print_routes_table(routes)
      end

      private

      def print_routes_table(routes)
        # Calculate column widths
        method_width = [routes.map { |r| r[:method].length }.max, 6].max
        path_width = [routes.map { |r| r[:path].length }.max, 4].max
        component_width = [routes.map { |r| r[:component].length }.max, 9].max
        helper_width = [routes.map { |r| (r[:helper] || "").length }.max, 10].max

        # Print header
        puts format_row("Method", "Path", "Component", "Helper",
                       method_width, path_width, component_width, helper_width)
        puts "-" * (method_width + path_width + component_width + helper_width + 12)

        # Print routes
        routes.each do |route|
          puts format_row(route[:method], route[:path], route[:component],
                         route[:helper] || "",
                         method_width, path_width, component_width, helper_width)
        end

        puts
        puts "Total: #{routes.length} route#{routes.length == 1 ? '' : 's'}"
      end

      def format_row(method, path, component, helper, mw, pw, cw, hw)
        "%-#{mw}s   %-#{pw}s   %-#{cw}s   %-#{hw}s" % [method, path, component, helper]
      end
    end
  end
end
