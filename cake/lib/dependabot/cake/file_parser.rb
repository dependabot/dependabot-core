# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"

module Dependabot
  module Cake
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "directives"

      def parse
        dependency_set = DependencySet.new

        cake_files.each do |cake_file|
          cake_file.content.each_line do |line|
            directive = Directives.parse_cake_directive_from(line)
            next if directive.nil?
            next unless supported_scheme?(directive.scheme)
            next unless directive.query.key?(:package)
            next unless directive.query.key?(:version)

            dependency_set << Dependency.new(
              name: directive.query[:package],
              version: directive.query[:version],
              package_manager: "cake",
              requirements: [{
                requirement: directive.query[:version],
                file: cake_file.name,
                groups: [],
                source: nil,
                metadata: { cake_directive: directive.to_h }
              }]
            )
          end
        end

        dependency_set.dependencies
      end

      private

      def supported_scheme?(scheme)
        %w(dotnet nuget).include?(scheme)
      end

      def cake_files
        dependency_files.select { |df| df.name.end_with?(".cake") }
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Cake file!"
      end
    end
  end
end

Dependabot::FileParsers.register("cake", Dependabot::Cake::FileParser)
