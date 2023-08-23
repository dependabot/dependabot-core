# typed: true
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/nuget/native_helpers"

module Dependabot
  module Nuget
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/property_value_updater"
      require_relative "file_parser/project_file_parser"
      require_relative "file_parser/packages_config_parser"

      def self.updated_files_regex
        [
          %r{^[^/]*\.([a-z]{2})?proj$},
          /^packages\.config$/i,
          /^global\.json$/i,
          /^dotnet-tools\.json$/i,
          /^Directory\.Build\.props$/i,
          /^Directory\.Build\.targets$/i,
          /^Packages\.props$/i
        ]
      end

      def updated_dependency_files
        # run update for each project file
        project_files.each do |project_file|
          project_dependencies = project_dependencies(project_file)

          directory_path = repository_directory_path(project_file)
          proj_path = dependency_file_path(project_file)
          dependencies.each do |dependency|
            # Check that the project references the dependency being updated.
            next unless project_dependencies.any? { |dep| dep.name.casecmp(dependency.name).zero? }

            NativeHelpers.run_nuget_updater_tool(directory_path, proj_path, dependency, !dependency.top_level?)
          end
        end

        # update all with content from disk
        updated_files = dependency_files.filter_map do |f|
          updated_content = File.read(dependency_file_path(f))
          next if updated_content == f.content

          normalized_content = normalize_content(f, updated_content)
          next if normalized_content == f.content

          puts "The contents of file [#{f.name}] were updated."

          updated_file(file: f, content: normalized_content)
        end

        # reset repo files
        SharedHelpers.reset_git_repo(T.cast(repo_contents_path, String)) if repo_contents_path

        updated_files
      end

      private

      def project_dependencies(project_file)
        # Collect all dependencies from the project file and associated packages.config
        dependencies = project_file_parser.dependency_set(project_file: project_file).dependencies
        packages_config = find_packages_config(project_file)
        return dependencies unless packages_config

        dependencies + FileParser::PackagesConfigParser.new(packages_config: packages_config)
                                                       .dependency_set.dependencies
      end

      def find_packages_config(project_file)
        project_file_name = File.basename(project_file.name)
        packages_config_path = project_file.name.gsub(project_file_name, "packages.config")
        packages_config_files.find { |f| f.name == packages_config_path }
      end

      def project_file_parser
        @project_file_parser ||=
          FileParser::ProjectFileParser.new(
            dependency_files: dependency_files,
            credentials: credentials
          )
      end

      def normalize_content(dependency_file, updated_content)
        # Fix up line endings
        if dependency_file.content.include?("\r\n") && updated_content.match?("(?!\r)\n")
          # The original content contain windows style newlines.
          # Ensure the updated content also uses windows style newlines.
          updated_content = updated_content.gsub("(?!\r)\n", "\r\n")
          puts "Fixing mismatched Windows line endings for [#{dependency_file.name}]."
        elsif updated_content.include?("\r\n")
          # The original content does not contain windows style newlines.
          # Ensure the updated content uses unix style newlines.
          updated_content = updated_content.gsub("\r\n", "\n")
          puts "Fixing mismatched Unix line endings for [#{dependency_file.name}]."
        end

        # Fix up BOM
        if dependency_file.content_encoding == "utf-8" && updated_content.start_with?("\uFEFF")
          updated_content = updated_content.delete_prefix("\uFEFF")
          puts "Removing BOM from [#{dependency_file.name}]."
        end

        updated_content
      end

      def repository_directory_path(dependency_file)
        # Since we may be running against a folder within a repo, we need to
        # determine that directory path. Dependency files are relative to the
        # folder we are running against, so we can use that to determine the
        # proper path.
        if dependency_file.directory.start_with?(repo_contents_path)
          dependency_file.directory
        else
          file_directory = dependency_file.directory
          file_directory = file_directory[1..-1] if file_directory.start_with?("/")
          File.join(repo_contents_path || "", file_directory)
        end
      end

      def dependency_file_path(dependency_file)
        if dependency_file.directory.start_with?(repo_contents_path)
          File.join(dependency_file.directory, dependency_file.name)
        else
          file_directory = dependency_file.directory
          file_directory = file_directory[1..-1] if file_directory.start_with?("/")
          File.join(repo_contents_path || "", file_directory, dependency_file.name)
        end
      end

      def project_files
        dependency_files.select { |df| df.name.match?(/\.([a-z]{2})?proj$/) }
      end

      def packages_config_files
        dependency_files.select do |f|
          T.must(T.must(f.name.split("/").last).casecmp("packages.config")).zero?
        end
      end

      def global_json
        dependency_files.find { |f| T.must(f.name.casecmp("global.json")).zero? }
      end

      def dotnet_tools_json
        dependency_files.find { |f| T.must(f.name.casecmp(".config/dotnet-tools.json")).zero? }
      end

      def check_required_files
        return if project_files.any? || packages_config_files.any?

        raise "No project file or packages.config!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::FileUpdater)
