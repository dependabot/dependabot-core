# typed: strict
# frozen_string_literal: true

require_relative "support/helpers"

namespace :rubocop do
  task :sort do
    File.write(
      "omnibus/.rubocop.yml",
      YAML.load_file("omnibus/.rubocop.yml").sort_by_key(true).to_yaml
    )
  end
end
