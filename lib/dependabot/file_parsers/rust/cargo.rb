# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Rust
      class Cargo < Dependabot::FileParsers::Base
        def parse
          # Parse the dependency files and return an array of
          # Dependabot::Dependency objects for each dependency.
          #
          # Looks like both the manifest and lockfile are just TOML, so we will
          # be able to do this in Ruby
          [
            Dependency.new(
              name: "my_dependency",
              version: "1.0.1",
              package_manager: "cargo",
              requirements: [{
                requirement: ">= 1.0.0",
                file: "Cargo.toml",
                groups: [],
                source: nil
              }]
            )
          ]
        end

        private

        def check_required_files
          %w(Cargo.toml Cargo.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end
      end
    end
  end
end
