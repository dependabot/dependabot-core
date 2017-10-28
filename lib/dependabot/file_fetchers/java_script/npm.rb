# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/file_parsers/java_script/npm"

module Dependabot
  module FileFetchers
    module JavaScript
      class Npm < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(package.json package-lock.json) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a package.json and a package-lock.json."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << package_json
          fetched_files << package_lock
          fetched_files += path_dependencies
          fetched_files
        end

        def package_json
          @package_json ||= fetch_file_from_github("package.json")
        end

        def package_lock
          @package_lock ||= fetch_file_from_github("package-lock.json")
        end

        def path_dependencies
          package_json_files = []
          unfetchable_deps = []

          types = Dependabot::FileParsers::JavaScript::Npm::DEPENDENCY_TYPES
          parsed_package_json.values_at(*types).compact.each do |deps|
            deps.map do |name, version|
              next unless version.start_with?("file:")

              path = version.sub(/^file:/, "")
              file = File.join(path, "package.json")

              begin
                package_json_files << fetch_file_from_github(file)
              rescue Dependabot::DependencyFileNotFound
                unfetchable_deps << name
              end
            end
          end

          if unfetchable_deps.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_deps
          end

          package_json_files
        end

        def parsed_package_json
          JSON.parse(package_json.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, package_json.path
        end
      end
    end
  end
end
