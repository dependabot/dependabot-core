# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Php
      class Composer < Dependabot::FileParsers::Base
        def parse
          runtime_dependencies + development_dependencies
        end

        private

        def runtime_dependencies
          parsed_composer_json.fetch("require", {}).map do |name, req|
            # Ignore dependencies which appear in the composer.json but not the
            # composer.lock. For instance, if a specific PHP version or
            # extension is required, it won't appear in the packages section of
            # the lockfile.
            next if dependency_version(name).nil?

            # Ignore dependency versions which are non-numeric, since they can't
            # be compared later in the process.
            next unless dependency_version(name).match?(/^\d/)

            Dependency.new(
              name: name,
              version: dependency_version(name),
              requirements: [{
                requirement: req,
                file: "composer.json",
                source: nil,
                groups: ["runtime"]
              }],
              package_manager: "composer"
            )
          end.compact
        end

        def development_dependencies
          parsed_composer_json.fetch("require-dev", {}).map do |name, req|
            # Ignore dependencies which appear in the composer.json but not the
            # composer.lock. For instance, if a specific PHP version or
            # extension is required, it won't appear in the packages section of
            # the lockfile.
            next if dependency_version(name).nil?

            # Ignore dependency versions which are non-numeric, since they can't
            # be compared later in the process.
            next unless dependency_version(name).match?(/^\d/)

            Dependency.new(
              name: name,
              version: dependency_version(name),
              requirements: [{
                requirement: req,
                file: "composer.json",
                source: nil,
                groups: ["development"]
              }],
              package_manager: "composer"
            )
          end.compact
        end

        def dependency_version(name)
          package = parsed_lockfile["packages"].find { |d| d["name"] == name }
          package&.fetch("version")&.sub(/^v?/, "")
        end

        def check_required_files
          %w(composer.json composer.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, lockfile.path
        end

        def parsed_composer_json
          @parsed_composer_json ||= JSON.parse(composer_json.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, composer_json.path
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
