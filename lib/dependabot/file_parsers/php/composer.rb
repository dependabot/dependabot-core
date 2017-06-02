# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/php/composer"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Php
      class Composer < Dependabot::FileParsers::Base
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
          package =
            parsed_lockfile["packages"].find { |dep| dep["name"] == name }
          package["version"]
        end

        def required_files
          Dependabot::FileFetchers::Php::Composer.required_files
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
