# frozen_string_literal: true
require "json"
require "bump/dependency"
require "bump/dependency_file_parsers/base"
require "bump/dependency_file_fetchers/java_script"

module Bump
  module DependencyFileParsers
    class JavaScript < Base
      def parse
        parsed_content = parser

        dependencies_hash = parsed_content["dependencies"] || {}
        dependencies_hash.merge!(parsed_content["devDependencies"] || {})

        # TODO: Taking the version from the package.json file here is naive -
        #       the version info found there is more likely in node-semver
        #       format than the exact current version. In future we should
        #       parse the yarn.lock file.

        dependencies_hash.map do |name, version|
          Dependency.new(
            name: name,
            version: version.match(/[\d\.]+/).to_s,
            language: "javascript"
          )
        end
      end

      private

      def required_files
        Bump::DependencyFileFetchers::JavaScript.required_files
      end

      def package_json
        @package_json ||= get_original_file("package.json")
      end

      def parser
        JSON.parse(package_json.content)
      end
    end
  end
end
