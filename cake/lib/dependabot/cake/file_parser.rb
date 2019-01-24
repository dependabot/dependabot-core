# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Cake
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      # Details of Cake preprocessor directives is at
      # https://cakebuild.net/docs/fundamentals/preprocessor-directives
      DIRECTIVE = /#(?<directive>addin|l|load|module|tool)/i.freeze
      SCHEME = /(?<scheme>choco|dotnet|local|nuget):/i.freeze
      SOURCE = /(?<source>[^?&"]+)/.freeze
      PACKAGE = /[?&]package=([^?&"]+)/i.freeze
      VERSION = /[?&]version=([^?&"]+)/i.freeze
      DIRECTIVE_LINE = /(?:^|")#{DIRECTIVE}\s+"?#{SCHEME}?#{SOURCE}?/.freeze

      def parse
        dependency_set = DependencySet.new

        cakefiles.each do |cakefile|
          cakefile.content.each_line do |line|
            next unless DIRECTIVE_LINE.match?(line)

            directive, scheme, _source, package, version = parse_line(line)
            next if scheme.nil? && %w(l load).include?(directive) ||
                    %w(choco local).include?(scheme) ||
                    package.nil? || version.nil?

            dependency_set << Dependency.new(
              name: package,
              version: version,
              package_manager: "nuget",
              requirements: [{
                requirement: version,
                file: cakefile.name,
                groups: [],
                source: nil
              }]
            )
          end
        end

        dependency_set.dependencies
      end

      private

      def parse_line(line)
        parsed_line = DIRECTIVE_LINE.match(line).named_captures

        [
          parsed_line.fetch("directive"),
          parsed_line.fetch("scheme"),
          parsed_line.fetch("source"),
          PACKAGE.match(line).captures.first,
          VERSION.match(line).captures.first
        ]
      end

      def cakefiles
        # The Cake file fetcher only fetches Cake files, so no need to
        # filter here
        dependency_files
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
