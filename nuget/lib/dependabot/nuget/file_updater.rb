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

      DependencyDetails = T.type_alias do
        {
          file: String,
          name: String,
          version: String,
          previous_version: String,
          is_transitive: T::Boolean
        }
      end
      
      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /.*\.([a-z]{2})?proj$/, # Matches files with any extension like .csproj, .vbproj, etc., in any directory
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
        SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          expanded_dependency_details.each do |dep_details|
            file = T.let(dep_details.fetch(:file), String)
            name = T.let(dep_details.fetch(:name), String)
            version = T.let(dep_details.fetch(:version), String)
            previous_version = T.let(dep_details.fetch(:previous_version), String)
            is_transitive = T.let(dep_details.fetch(:is_transitive), T::Boolean)
            NativeHelpers.run_nuget_updater_tool(repo_root: T.must(repo_contents_path),
                                                 proj_path: file,
                                                 dependency_name: name,
                                                 version: version,
                                                 previous_version: previous_version,
                                                 is_transitive: is_transitive,
                                                 credentials: credentials)
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

      # rubocop:disable Metrics/AbcSize
      sig { returns(T::Array[DependencyDetails]) }
      def expanded_dependency_details
        discovery_json_reader = NativeDiscoveryJsonReader.get_discovery_from_dependency_files(dependency_files)
        dependency_set = discovery_json_reader.dependency_set(dependency_files: dependency_files, top_level_only: false)
        all_dependencies = dependency_set.dependencies
        dependencies.map do |dep|
          # if vulnerable metadata is set, re-fetch all requirements from discovery
          is_vulnerable = T.let(dep.metadata.fetch(:is_vulnerable, false), T::Boolean)
          relevant_dependencies = all_dependencies.filter { |d| d.name.casecmp?(dep.name) }
          candidate_vulnerable_dependency = T.must(relevant_dependencies.first)
          relevant_dependency = is_vulnerable ? candidate_vulnerable_dependency : dep
          relevant_details = relevant_dependency.requirements.filter_map do |req|
            dependency_details_from_requirement(dep.name, req, is_vulnerable: is_vulnerable)
          end

          next relevant_details if relevant_details.any?

          # If we didn't find anything to update, we're in a very specific corner case: we were explicitly asked to
          # (1) update a certain dependency, (2) it wasn't listed as a security update, but (3) it only exists as a
          # transitive dependency.  In this case, we need to rebuild the dependency requirements as if this were a
          # security update so that we can perform the appropriate update.
          candidate_vulnerable_dependency.requirements.filter_map do |req|
            rebuilt_req = {
              file: req[:file], # simple copy
              requirement: relevant_dependency.version, # the newly available version
              metadata: {
                is_transitive: T.let(req[:metadata], T::Hash[Symbol, T.untyped])[:is_transitive], # simple copy
                previous_requirement: req[:requirement] # the old requirement's "current" version is now the "previous"
              }
            }
            dependency_details_from_requirement(dep.name, rebuilt_req, is_vulnerable: true)
          end
        end.flatten
      end
      # rubocop:enable Metrics/AbcSize

      sig do
        params(
          name: String,
          requirement: T::Hash[Symbol, T.untyped],
          is_vulnerable: T::Boolean
        ).returns(T.nilable(DependencyDetails))
      end
      def dependency_details_from_requirement(name, requirement, is_vulnerable:)
        metadata = T.let(requirement.fetch(:metadata), T::Hash[Symbol, T.untyped])
        current_file = T.let(requirement.fetch(:file), String)
        return nil unless current_file.match?(/\.(cs|vb|fs)proj$/)

        is_transitive = T.let(metadata.fetch(:is_transitive), T::Boolean)
        return nil if !is_vulnerable && is_transitive

        version = T.let(requirement.fetch(:requirement), String)
        previous_version = T.let(metadata[:previous_requirement], String)
        return nil if version == previous_version

        {
          file: T.let(requirement.fetch(:file), String),
          name: name,
          version: version,
          previous_version: previous_version,
          is_transitive: is_transitive
        }
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
