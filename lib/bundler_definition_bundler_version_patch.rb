# frozen_string_literal: true

require "bundler/definition"

# Ignore the Bundler version specified in the Gemfile (since the only Bundler
# version available to us is the one we're using).
module Bundler
  class Definition
    def expanded_dependencies
      @expanded_dependencies ||=
        expand_dependencies(dependencies + metadata_dependencies, @remote).
        reject { |d| d.name == "bundler" }
    end
  end
end
