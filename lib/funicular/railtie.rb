# frozen_string_literal: true

require "rails/railtie"

module Funicular
  class Railtie < Rails::Railtie
    railtie_name :funicular

    initializer "funicular.middleware" do |app|
      if Rails.env.development?
        app.middleware.use Funicular::Middleware
      end
    end

    rake_tasks do
      load "tasks/funicular.rake"
    end
  end
end
