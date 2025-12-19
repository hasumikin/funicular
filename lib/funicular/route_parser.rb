# frozen_string_literal: true

module Funicular
  class RouteParser
    attr_reader :routes

    def initialize(source_file)
      @source_file = source_file
      @routes = []
    end

    def parse
      return [] unless File.exist?(@source_file)

      content = File.read(@source_file)
      lines = content.split("\n")

      lines.each do |line|
        # Skip comments and empty lines
        trimmed = line.strip
        next if trimmed.empty? || trimmed.start_with?('#')

        # Parse router.get/post/put/patch/delete lines
        if trimmed.include?('router.')
          parse_route_line(trimmed)
        end
      end

      @routes
    end

    private

    def parse_route_line(line)
      # Extract HTTP method
      method = nil
      ['get', 'post', 'put', 'patch', 'delete', 'add_route'].each do |m|
        if line.include?("router.#{m}")
          method = m
          break
        end
      end

      return unless method

      # Extract path (between first pair of quotes)
      path = extract_quoted_string(line)
      return unless path

      # Extract component name (after 'to:' or as second argument)
      component = nil
      if line.include?('to:')
        to_idx = line.index('to:')
        if to_idx
          # Component name is after 'to:'
          after_to = line[to_idx + 3..-1].strip
          # Find where component name ends (comma or paren)
          end_idx = find_first_of(after_to, [',', ')'])
          if end_idx
            component = after_to[0...end_idx].strip
          else
            component = after_to.strip
          end
        end
      elsif method == 'add_route'
        # Old style: router.add_route('/path', ComponentName)
        # Find second comma-separated value
        first_comma = line.index(',')
        if first_comma
          after_comma = line[first_comma + 1..-1].strip
          # Component name ends at comma or paren
          end_idx = find_first_of(after_comma, [',', ')'])
          if end_idx
            component = after_comma[0...end_idx].strip
          else
            component = after_comma.strip
          end
        end
      end

      return unless component

      # Extract helper name (after 'as:')
      helper_name = nil
      if line.include?('as:')
        as_idx = line.index('as:')
        if as_idx
          after_as = line[as_idx + 3..-1]
          helper_str = extract_quoted_string(after_as)
          helper_name = helper_str ? "#{helper_str}_path" : nil
        end
      end

      # Add route
      @routes << {
        method: method == 'add_route' ? 'GET' : method.upcase,
        path: path,
        component: component,
        helper: helper_name
      }
    end

    def extract_quoted_string(text)
      # Find first quoted string (single or double quotes)
      start_idx = nil
      quote_char = nil

      text.each_char.with_index do |char, idx|
        if char == '"' || char == "'"
          if start_idx.nil?
            start_idx = idx
            quote_char = char
          elsif char == quote_char
            # Found closing quote
            return text[(start_idx + 1)...idx]
          end
        end
      end

      nil
    end

    def find_first_of(text, chars)
      # Find index of first occurrence of any char in chars array
      min_idx = nil

      chars.each do |char|
        idx = text.index(char)
        if idx
          min_idx = idx if min_idx.nil? || idx < min_idx
        end
      end

      min_idx
    end
  end
end
