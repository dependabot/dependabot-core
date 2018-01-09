# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module CSharp
      class Nuget < Dependabot::FileParsers::Base
        def parse
          # Parse the dependency file and return a Dependabot::Dependency
          # object for each dependency.
          # If possible, this should be done in Ruby (since it's easier to
          # maintain). However, if we need to parse a lockfile that has a
          # non-standard format we can shell out to a helper in a language of
          # our choice (see JavaScript example where we parse the yarn.lock).
          [
            Dependency.new(
              name: "my_dependency",
              version: "1.0.1",
              package_manager: "nuget",
              requirements: [{
                requirement: ">= 1.0.0",
                file: "paket.dependencies",
                groups: [],
                source: nil
              }]
            )
          ]
        end

        private

        def check_required_files
          %w(paket.dependencies paket.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end
      end
    end
  end
end
