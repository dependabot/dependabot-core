# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Php
      class Composer < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_GROUP_KEYS = [
          {
            manifest: "require",
            lockfile: "packages",
            group: "runtime"
          },
          {
            manifest: "require-dev",
            lockfile: "packages-dev",
            group: "development"
          }
        ].freeze

        def parse
          dependency_set = DependencySet.new
          dependency_set += manifest_dependencies
          dependency_set.dependencies
        end

        private

        def manifest_dependencies
          dependencies = DependencySet.new

          DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless parsed_composer_json[keys[:manifest]]
            parsed_composer_json[keys[:manifest]].each do |name, req|
              next unless package?(name)

              if lockfile
                version = dependency_version(name: name, type: keys[:group])

                # Ignore dependencies which appear in the composer.json but not
                # the composer.lock.
                next if version.nil?

                # Ignore dependency versions which are non-numeric, since they
                # can't be compared later in the process.
                next unless version.match?(/^\d/)
              end

              dependencies <<
                Dependency.new(
                  name: name,
                  version: dependency_version(name: name, type: keys[:group]),
                  requirements: [{
                    requirement: req,
                    file: "composer.json",
                    source: dependency_source(name: name, type: keys[:group]),
                    groups: [keys[:group]]
                  }],
                  package_manager: "composer"
                )
            end
          end

          dependencies
        end

        def dependency_version(name:, type:)
          return unless lockfile
          key = lockfile_key(type)
          package = parsed_lockfile.fetch(key).find { |d| d["name"] == name }
          package&.fetch("version")&.sub(/^v?/, "")
        end

        def dependency_source(name:, type:)
          return unless lockfile
          key = lockfile_key(type)
          package = parsed_lockfile.fetch(key).find { |d| d["name"] == name }
          return unless package&.dig("source", "type") == "git"
          {
            type: "git",
            url: package.dig("source", "url")
          }
        end

        def lockfile_key(type)
          case type
          when "runtime" then "packages"
          when "development" then "packages-dev"
          else raise "unknown type #{type}"
          end
        end

        def package?(name)
          # Filter out php, ext-, composer-plugin-api, and other special
          # packages which don't behave as normal
          name.split("/").count == 2
        end

        def check_required_files
          raise "No composer.json!" unless get_original_file("composer.json")
        end

        def parsed_lockfile
          return unless lockfile
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
