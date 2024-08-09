# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/nuget/native_discovery/native_dependency_details"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/nuget/native_discovery/native_workspace_discovery"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^.*\.([a-z]{2})?proj$/,
          /^packages\.config$/i,
          /^app\.config$/i,
          /^web\.config$/i,
          /^global\.json$/i,
          /^dotnet-tools\.json$/i,
          /^Directory\.Build\.props$/i,
          /^Directory\.Build\.targets$/i,
          /^Packages\.props$/i
        ]
      end

      sig { params(original_content: T.nilable(String), updated_content: String).returns(T::Boolean) }
      def self.differs_in_more_than_blank_lines?(original_content, updated_content)
        # Compare the line counts of the original and updated content, but ignore lines only containing white-space.
        # This prevents false positives when there are trailing empty lines in the original content, for example.
        original_lines = (original_content&.lines || []).map(&:strip).reject(&:empty?)
        updated_lines = updated_content.lines.map(&:strip).reject(&:empty?)

        # if the line count differs, then something changed
        return true unless original_lines.count == updated_lines.count

        # check each line pair, ignoring blanks (filtered above)
        original_lines.zip(updated_lines).any? { |pair| pair[0] != pair[1] }
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        base_dir = "/"
        SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          dependencies.each do |dependency|
            try_update_projects(dependency) || try_update_json(dependency)
          end
          updated_files = dependency_files.filter_map do |f|
            updated_content = File.read(dependency_file_path(f))
            next if updated_content == f.content

            normalized_content = normalize_content(f, updated_content)
            next if normalized_content == f.content

            next unless FileUpdater.differs_in_more_than_blank_lines?(f.content, normalized_content)

            puts "The contents of file [#{f.name}] were updated."

            updated_file(file: f, content: normalized_content)
          end
          updated_files
        end
      end

      private

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def try_update_projects(dependency)
        update_ran = T.let(false, T::Boolean)
        checked_files = Set.new

        # run update for each project file
        project_files.each do |project_file|
          project_dependencies = project_dependencies(project_file)
          proj_path = dependency_file_path(project_file)

          next unless project_dependencies.any? { |dep| dep.name.casecmp?(dependency.name) }

          next unless repo_contents_path

          checked_key = "#{project_file.name}-#{dependency.name}#{dependency.version}"
          call_nuget_updater_tool(dependency, proj_path) unless checked_files.include?(checked_key)

          checked_files.add(checked_key)
          # We need to check the downstream references even though we're already evaluated the file
          downstream_files = referenced_project_paths(project_file)
          downstream_files.each do |downstream_file|
            checked_files.add("#{downstream_file}-#{dependency.name}#{dependency.version}")
          end
          update_ran = true
        end
        update_ran
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def try_update_json(dependency)
        if dotnet_tools_json_dependencies.any? { |dep| dep.name.casecmp?(dependency.name) } ||
           global_json_dependencies.any? { |dep| dep.name.casecmp?(dependency.name) }

          # We just need to feed the updater a project file, grab the first
          project_file = T.must(project_files.first)
          proj_path = dependency_file_path(project_file)

          return false unless repo_contents_path

          call_nuget_updater_tool(dependency, proj_path)
          return true
        end

        false
      end

      sig { params(dependency: Dependency, proj_path: String).void }
      def call_nuget_updater_tool(dependency, proj_path)
        NativeHelpers.run_nuget_updater_tool(repo_root: T.must(repo_contents_path), proj_path: proj_path,
                                             dependency: dependency, is_transitive: !dependency.top_level?,
                                             credentials: credentials)

        # Tests need to track how many times we call the tooling updater to ensure we don't recurse needlessly
        # Ideally we should find a way to not run this code in prod
        # (or a better way to track calls made to NativeHelpers)
        @update_tooling_calls ||= T.let({}, T.nilable(T::Hash[String, Integer]))
        key = "#{proj_path.delete_prefix(T.must(repo_contents_path))}+#{dependency.name}"
        @update_tooling_calls[key] =
          if @update_tooling_calls[key]
            T.must(@update_tooling_calls[key]) + 1
          else
            1
          end
      end

      # Don't call this from outside tests, we're only checking that we aren't recursing needlessly
      sig { returns(T.nilable(T::Hash[String, Integer])) }
      def testonly_update_tooling_calls
        @update_tooling_calls
      end

      sig { returns(T.nilable(NativeWorkspaceDiscovery)) }
      def workspace
        discovery_json_reader = NativeDiscoveryJsonReader.get_discovery_from_dependency_files(dependency_files)
        discovery_json_reader.workspace_discovery
      end

      sig { params(project_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def referenced_project_paths(project_file)
        workspace&.projects&.find { |p| p.file_path == project_file.name }&.referenced_project_paths || []
      end

      sig { params(project_file: Dependabot::DependencyFile).returns(T::Array[NativeDependencyDetails]) }
      def project_dependencies(project_file)
        workspace&.projects&.find do |p|
          full_project_file_path = File.join(project_file.directory, project_file.name)
          p.file_path == full_project_file_path
        end&.dependencies || []
      end

      sig { returns(T::Array[NativeDependencyDetails]) }
      def global_json_dependencies
        workspace&.global_json&.dependencies || []
      end

      sig { returns(T::Array[NativeDependencyDetails]) }
      def dotnet_tools_json_dependencies
        workspace&.dotnet_tools_json&.dependencies || []
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(dependency_file: Dependabot::DependencyFile, updated_content: String).returns(String) }
      def normalize_content(dependency_file, updated_content)
        # Fix up line endings
        if dependency_file.content&.include?("\r\n")
          # The original content contain windows style newlines.
          if updated_content.match?(/(?<!\r)\n/)
            # Ensure the updated content also uses windows style newlines.
            updated_content = updated_content.gsub(/(?<!\r)\n/, "\r\n")
            puts "Fixing mismatched Windows line endings for [#{dependency_file.name}]."
          end
        elsif updated_content.include?("\r\n")
          # The original content does not contain windows style newlines, but the updated content does.
          # Ensure the updated content uses unix style newlines.
          updated_content = updated_content.gsub("\r\n", "\n")
          puts "Fixing mismatched Unix line endings for [#{dependency_file.name}]."
        end

        # Fix up BOM
        if !dependency_file.content&.start_with?("\uFEFF") && updated_content.start_with?("\uFEFF")
          updated_content = updated_content.delete_prefix("\uFEFF")
          puts "Removing BOM from [#{dependency_file.name}]."
        elsif dependency_file.content&.start_with?("\uFEFF") && !updated_content.start_with?("\uFEFF")
          updated_content = "\uFEFF" + updated_content
          puts "Adding BOM to [#{dependency_file.name}]."
        end

        updated_content
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(dependency_file: Dependabot::DependencyFile).returns(String) }
      def dependency_file_path(dependency_file)
        if dependency_file.directory.start_with?(T.must(repo_contents_path))
          File.join(dependency_file.directory, dependency_file.name)
        else
          file_directory = dependency_file.directory
          file_directory = file_directory[1..-1] if file_directory.start_with?("/")
          File.join(repo_contents_path || "", file_directory, dependency_file.name)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_files
        dependency_files.select { |df| df.name.match?(/\.(cs|vb|fs)proj$/) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def packages_config_files
        dependency_files.select do |f|
          T.must(T.must(f.name.split("/").last).casecmp("packages.config")).zero?
        end
      end

      sig { override.void }
      def check_required_files
        return if project_files.any? || packages_config_files.any?

        raise "No project file or packages.config!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::FileUpdater)
