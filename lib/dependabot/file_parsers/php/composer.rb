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

          dependencies = parsed_composer_json.fetch("require", {}).keys

          # TODO: Add support for development dependencies. Will need to be
          # added to file updaters, too.

          dependencies.map do |name|
            # Ignore dependencies which appear in the composer.json but not the
            # composer.lock. For instance, if a specific PHP version or
            # extension is required, it won't appear in the packages section of
            # the lockfile.
            next if dependency_version(name).nil?

            Dependency.new(
              name: name,
              version: dependency_version(name),
              package_manager: "composer"
            )
          end.compact
        end

        private

        def dependency_version(name)
          package = parsed_lockfile["packages"].find { |d| d["name"] == name }
          package&.fetch("version")&.sub(/^v?/, "")
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
