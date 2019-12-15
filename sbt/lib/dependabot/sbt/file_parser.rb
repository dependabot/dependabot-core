# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module Sbt
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/scala_versions_finder"

      DEPENDENCY_DECLARATION_REGEX =
        /
        ^.*=.*?\"(?<group>.*?)\".*?%(?<cross_build>%?)\s+
        \"(?<name>.*?)\"\s+?%\s+?\"(?<version>.*?)\".*$
        /x.freeze

      def parse
        dependency_set = DependencySet.new
        buildfiles.each do |buildfile|
          dependency_set += buildfile_dependencies(buildfile)
        end
        dependency_set.dependencies
      end

      private

      def check_required_files
        raise "No build.sbt!" unless get_original_file("build.sbt")
      end

      def buildfiles
        @buildfiles ||= dependency_files.select do |file|
          %w(.sbt .scala).include? File.extname(file.name)
        end
      end

      def buildfile_dependencies(buildfile)
        dependency_set = DependencySet.new
        dependency_set += sbt_or_project_scala_files(buildfile)
        dependency_set
      end

      def sbt_or_project_scala_files(buildfile)
        dependency_set = DependencySet.new

        prepared_content(buildfile).scan(DEPENDENCY_DECLARATION_REGEX) do
          named_captures = Regexp.last_match.named_captures

          case named_captures.fetch("cross_build")
          when "%"
            scala_versions = scala_versions_finder.cross_build_versions
            version_suffix = if scala_versions.empty?
                               ""
                             else
                               "_" + scala_versions.first
                             end
          else
            scala_versions = []
            version_suffix = ""
          end

          name = named_captures.fetch("name") + version_suffix
          group = named_captures.fetch("group")
          version = named_captures.fetch("version")

          details = { group: group, name: name, version: version }

          dep = dependency_from(details_hash: details, buildfile: buildfile,
                                scala_versions: scala_versions)
          dependency_set << dep if dep
        end

        dependency_set
      end

      def dependency_from(details_hash:, buildfile:, scala_versions:)
        group   = details_hash[:group]
        name    = details_hash[:name]
        version = details_hash[:version]

        source = nil

        Dependency.new(
          name: "#{group}:#{name}",
          version: version,
          requirements: [{
            requirement: version,
            file: buildfile.name,
            source: source,
            groups: [],
            metadata: {
              cross_scala_versions: scala_versions
            }
          }],
          package_manager: "sbt"
        )
      end

      def prepared_content(buildfile)
        # remove comments
        buildfile.content.
          gsub(%r{(?<=^|\s)//.*$}, "\n"). # line beginning '//'
          gsub(%r{(?<=^|\s)/\*.*?\*/}m, "") # multiline with '/* ... */'
      end

      def scala_versions_finder
        ScalaVersionsFinder.new(dependency_files: buildfiles)
      end
    end
  end
end

Dependabot::FileParsers.register("sbt", Dependabot::Sbt::FileParser)
