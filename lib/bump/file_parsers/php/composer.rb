# frozen_string_literal: true
require "bump/dependency"
require "bump/file_parsers/base"
require "bump/file_fetchers/php/composer"
require "bump/shared_helpers"

module Bump
  module FileParsers
    module Php
      class Composer < Bump::FileParsers::Base
        def parse
          parsed_composer_json = JSON.parse(composer_json.content)

          parsed_composer_json["require"].map do |name, _|
            Dependency.new(
              name: name,
              version: dependency_version(name),
              package_manager: "composer"
            )
          end
        end

        private

        def dependency_version(name)
          package = parsed_lockfile["packages"].find { |dep| dep["name"] == name }
          package["version"]
        end

        def required_files
          Bump::FileFetchers::Php::Composer.required_files
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        end

        def parsed_composer_json
          @parsed_composer_json ||= JSON.parse(composer_json.content)
        end

        def composer_json
          @composer_json ||= get_original_file("composer.json")
        end

        def lockfile
          @lockfile ||= get_original_file("composer.lock")
        end
      end
    end
  end
end
