# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/nuget/discovery/dependency_details"
require "dependabot/nuget/discovery/discovery_json_reader"
require "dependabot/nuget/discovery/workspace_discovery"
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
          /.*\.([a-z]{2})?proj$/, # Matches files with any extension like .csproj, .vbproj, etc., in any directory
          /packages\.lock\.json/,         # Matches packages.lock.json in any directory
          /packages\.config$/i,           # Matches packages.config in any directory
          /app\.config$/i,                # Matches app.config in any directory
          /web\.config$/i,                # Matches web.config in any directory
          /global\.json$/i,               # Matches global.json in any directory
          /dotnet-tools\.json$/i,         # Matches dotnet-tools.json in any directory
          /Directory\.Build\.props$/i,    # Matches Directory.Build.props in any directory
          /Directory\.Build\.targets$/i,  # Matches Directory.Build.targets in any directory
          /Directory\.targets$/i,         # Matches Directory.targets in any directory or root directory
          /Packages\.props$/i, # Matches Packages.props in any directory
          /.*\.nuspec$/, # Matches any .nuspec files in any directory
          %r{^\.config/dotnet-tools\.json$} # Matches .config/dotnet-tools.json in only root directory
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
        all_updated_files = SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          dependencies.each do |dependency|
            try_update_projects(dependency) || try_update_json(dependency)
          end
          updated_files = dependency_files.filter_map do |f|
            dependency_file_path = DiscoveryJsonReader.dependency_file_path(
              repo_contents_path: T.must(repo_contents_path),
              dependency_file: f
            )
            dependency_file_path = File.join(repo_contents_path, dependency_file_path)
            updated_content = File.read(dependency_file_path)
            next if updated_content == f.content

            normalized_content = normalize_content(f, updated_content)
            next if normalized_content == f.content

            next unless FileUpdater.differs_in_more_than_blank_lines?(f.content, normalized_content)

            puts "The contents of file [#{f.name}] were updated."

            updated_file(file: f, content: normalized_content)
          end
          updated_files
        end

        raise UpdateNotPossible, dependencies.map(&:name) if all_updated_files.empty?

        all_updated_files
      end

      private

      sig { returns(String) }
      def job_file_path
        ENV.fetch("DEPENDABOT_JOB_PATH")
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def try_update_projects(dependency)
        update_ran = T.let(false, T::Boolean)
        checked_files = Set.new

        # run update for each project file
        project_files.each do |project_file|
          project_dependencies = project_dependencies(project_file)
          dependency_file_path = DiscoveryJsonReader.dependency_file_path(
            repo_contents_path: T.must(repo_contents_path),
            dependency_file: project_file
          )
          proj_path = dependency_file_path

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
          dependency_file_path = DiscoveryJsonReader.dependency_file_path(
            repo_contents_path: T.must(repo_contents_path),
            dependency_file: project_file
          )
          proj_path = dependency_file_path

          return false unless repo_contents_path

          call_nuget_updater_tool(dependency, proj_path)
          return true
        end

        false
      end

      sig { params(dependency: Dependency, proj_path: String).void }
      def call_nuget_updater_tool(dependency, proj_path)
        NativeHelpers.run_nuget_updater_tool(job_path: job_file_path, repo_root: T.must(repo_contents_path),
                                             proj_path: proj_path, dependency: dependency,
                                             is_transitive: !dependency.top_level?, credentials: credentials)

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

      sig { returns(T.nilable(WorkspaceDiscovery)) }
      def workspace
        dependency_file_paths = dependency_files.map do |f|
          DiscoveryJsonReader.dependency_file_path(repo_contents_path: T.must(repo_contents_path),
                                                   dependency_file: f)
        end
        DiscoveryJsonReader.load_discovery_for_dependency_file_paths(dependency_file_paths).workspace_discovery
      end

      sig { params(project_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def referenced_project_paths(project_file)
        workspace&.projects&.find { |p| p.file_path == project_file.name }&.referenced_project_paths || []
      end

      sig { params(project_file: Dependabot::DependencyFile).returns(T::Array[DependencyDetails]) }
      def project_dependencies(project_file)
        workspace&.projects&.find do |p|
          full_project_file_path = File.join(project_file.directory, project_file.name)
          p.file_path == full_project_file_path
        end&.dependencies || []
      end

      sig { returns(T::Array[DependencyDetails]) }
      def global_json_dependencies
        workspace&.global_json&.dependencies || []
      end

      sig { returns(T::Array[DependencyDetails]) }
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
