# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "tempfile"
require "fileutils"
require "pathname"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/julia/registry_client"
require "dependabot/notices"

module Dependabot
  module Julia
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/(?:Julia)?Project\.toml$/i, /(?:Julia)?Manifest(?:-v[\d.]+)?\.toml$/i]
      end

      sig { override.returns(T::Array[Dependabot::Notice]) }
      attr_reader :notices

      sig do
        override.params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path: nil, options: {})
        super
        @notices = T.let([], T::Array[Dependabot::Notice])
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        # If no project file, cannot proceed
        raise "No Project.toml file found" unless project_file

        # Use DependabotHelper.jl for manifest updating
        # This works for both standard packages and workspace packages
        updated_files_with_julia_helper
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_files_with_julia_helper
        updated_files = []

        SharedHelpers.in_a_temporary_repo_directory(T.must(dependency_files.first).directory, repo_contents_path) do
          updated_project = updated_project_content
          actual_manifest = find_manifest_file

          return project_only_update(updated_project) if actual_manifest.nil?

          # Work directly in the repo directory - no need for another temp directory
          # This ensures all workspace packages are accessible to Julia's Pkg
          write_temporary_files(updated_project, actual_manifest)
          result = call_julia_helper

          return handle_julia_helper_error(result, actual_manifest, updated_project) if result["error"]

          build_updated_files(updated_files, updated_project, actual_manifest, result)
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      sig { params(updated_project: String).returns(T::Array[Dependabot::DependencyFile]) }
      def project_only_update(updated_project)
        [updated_file(file: T.must(project_file), content: updated_project)]
      end

      sig do
        params(
          updated_project: String,
          actual_manifest: Dependabot::DependencyFile
        ).void
      end
      def write_temporary_files(updated_project, actual_manifest)
        File.write(T.must(project_file).name, updated_project)

        # Preserve relative paths (e.g., ../Manifest.toml for workspace packages)
        # so Julia's Pkg can find and update the correct shared manifest
        manifest_path = actual_manifest.name
        FileUtils.mkdir_p(File.dirname(manifest_path)) if manifest_path.include?("/")
        File.write(manifest_path, actual_manifest.content)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def call_julia_helper
        registry_client.update_manifest(
          project_path: Dir.pwd,
          updates: build_updates_hash
        )
      end

      sig do
        params(
          result: T::Hash[String, T.untyped],
          actual_manifest: Dependabot::DependencyFile,
          updated_project: String
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def handle_julia_helper_error(result, actual_manifest, updated_project)
        error_message = result["error"]
        manifest_path = actual_manifest.name

        is_resolver_error = resolver_error?(error_message)
        raise error_message unless is_resolver_error

        add_manifest_update_notice(manifest_path, error_message)

        # Return only the updated Project.toml
        [updated_file(file: T.must(project_file), content: updated_project)]
      end

      sig { params(error_message: String).returns(T::Boolean) }
      def resolver_error?(error_message)
        error_message.start_with?("Pkg resolver error:") ||
          error_message.include?("Unsatisfiable requirements") ||
          error_message.include?("ResolverError")
      end

      sig { params(manifest_path: String, error_message: String).void }
      def add_manifest_update_notice(manifest_path, error_message)
        # Resolve relative paths to absolute paths for clarity in user-facing notices
        # Use Pathname.cleanpath to handle any depth of relative paths (e.g., ../../Manifest.toml)
        project_dir = T.must(project_file).directory
        absolute_manifest_path = if manifest_path.start_with?("../", "./")
                                   # For workspace packages, compute the absolute path
                                   Pathname.new(File.join(project_dir, manifest_path)).cleanpath.to_s
                                 else
                                   # For regular packages, use the manifest path as-is
                                   File.join(project_dir, manifest_path)
                                 end

        @notices << Dependabot::Notice.new(
          mode: Dependabot::Notice::NoticeMode::WARN,
          type: "julia_manifest_not_updated",
          package_manager_name: "Pkg",
          title: "Could not update manifest #{absolute_manifest_path}",
          description: "The Julia package manager failed to update the new dependency versions " \
                       "in `#{absolute_manifest_path}`:\n\n```\n#{error_message}\n```",
          show_in_pr: true,
          show_alert: true
        )
      end

      sig do
        params(
          updated_files: T::Array[Dependabot::DependencyFile],
          updated_project: String,
          actual_manifest: Dependabot::DependencyFile,
          result: T::Hash[String, T.untyped]
        ).void
      end
      def build_updated_files(updated_files, updated_project, actual_manifest, result)
        updated_files << updated_file(file: T.must(project_file), content: updated_project)

        return unless result["manifest_content"]

        updated_manifest_content = result["manifest_content"]
        return unless updated_manifest_content != actual_manifest.content

        manifest_for_update = if result["manifest_path"]
                                manifest_file_for_path(result["manifest_path"])
                              else
                                actual_manifest
                              end
        updated_files << updated_file(file: manifest_for_update, content: updated_manifest_content)
      end

      private

      sig { returns(T::Hash[String, String]) }
      def build_updates_hash
        updates = {}
        dependencies.each do |dependency|
          next unless dependency.version

          uuid = T.cast(dependency.metadata[:julia_uuid], String)
          updates[uuid] = {
            "name" => dependency.name,
            "version" => dependency.version
          }
        end
        updates
      end

      # Helper methods for DependabotHelper.jl integration

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Julia::RegistryClient.new(
            credentials: credentials
          ),
          T.nilable(Dependabot::Julia::RegistryClient)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def find_manifest_file
        # The file fetcher has already identified the correct manifest file
        # For regular packages: manifest in same directory
        # For workspace packages: manifest in parent directory
        # We just need to find it in dependency_files
        project_dir = T.must(project_file).directory

        dependency_files.find do |f|
          # Use basename to get just the filename, not the full path with ../
          is_manifest = File.basename(f.name).match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)
          is_manifest && (f.directory == project_dir || project_dir.start_with?(f.directory))
        end
      end

      sig { params(manifest_path: String).returns(Dependabot::DependencyFile) }
      def manifest_file_for_path(manifest_path)
        # manifest_path is relative to the project directory (e.g., "Manifest.toml" or "../Manifest.toml")
        # We need to resolve it to find the actual manifest file in dependency_files

        # Build the absolute path relative to the project directory
        project_dir = T.must(project_file).directory
        resolved_manifest_path = File.expand_path(manifest_path, project_dir)

        # Normalize by removing leading "/" to get repo-relative path
        resolved_manifest_path = resolved_manifest_path.sub(%r{^/}, "")

        # Find the matching manifest file in dependency_files
        found_manifest = dependency_files.find do |f|
          next unless f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)

          # Construct the full path for this file and normalize it
          file_path = File.join(f.directory, f.name).sub(%r{^/}, "")
          file_path == resolved_manifest_path
        end

        # If we found the manifest file and the manifest_path matches its name exactly,
        # return the original file to preserve its metadata
        return found_manifest if found_manifest && found_manifest.name == manifest_path

        # For workspace cases where manifest_path is relative (e.g., "../Manifest.toml"),
        # we need to create a new DependencyFile with the relative path as its name,
        # but copy the content from the found manifest if it exists
        Dependabot::DependencyFile.new(
          name: manifest_path,
          content: found_manifest&.content || "",
          directory: project_dir
        )
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.empty?

        return if dependency_files.any? { |f| f.name.match?(/^(Julia)?Project\.toml$/i) }

        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found."
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          dependency_files.find do |f|
            f.name.match?(/^(Julia)?Project\.toml$/i)
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def updated_project_content
        return T.must(T.must(project_file).content) unless project_file

        content = T.must(T.must(project_file).content)

        dependencies.each do |dependency|
          # Find the new requirement for this dependency
          new_requirement = dependency.requirements
                                      .find { |req| T.cast(req[:file], String) == T.must(project_file).name }
                                      &.fetch(:requirement)

          next unless new_requirement

          content = update_dependency_requirement_in_content(content, dependency.name, new_requirement)
        end

        content
      end

      sig { params(content: String, dependency_name: String, new_requirement: String).returns(String) }
      def update_dependency_requirement_in_content(content, dependency_name, new_requirement)
        # Extract the [compat] section to update it specifically
        compat_section_match = content.match(/^\[compat\]\s*\n((?:(?!\[)[^\n]*\n)*?)(?=^\[|\z)/m)

        if compat_section_match
          compat_section = T.must(compat_section_match[1])
          # Pattern to match the dependency in the compat section
          pattern = /^(\s*#{Regexp.escape(dependency_name)}\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s#\n]+)(\s*(?:\#.*)?)$/

          if compat_section.match?(pattern)
            # Replace existing entry in compat section
            updated_compat = compat_section.gsub(pattern, "\\1\"#{new_requirement}\"\\2")
            content.sub(T.must(compat_section_match[0]), "[compat]\n#{updated_compat}")
          else
            # Add new entry to existing [compat] section
            add_compat_entry_to_content(content, dependency_name, new_requirement)
          end
        else
          # Add new [compat] section
          add_compat_entry_to_content(content, dependency_name, new_requirement)
        end
      end

      sig { params(content: String, dependency_name: String, requirement: String).returns(String) }
      def add_compat_entry_to_content(content, dependency_name, requirement)
        if content.match?(/^\s*\[compat\]\s*$/m)
          compat_section_match = content.match(/^\[compat\]\s*\n((?:(?!\[)[^\n]*\n)*?)(?=^\[|\z)/m)
          return content unless compat_section_match

          compat_section = T.must(compat_section_match[1])
          entries = parse_compat_entries(compat_section)
          entries[dependency_name] = requirement
          sorted_entries = sort_compat_entries(entries)
          new_compat_section = build_compat_section(sorted_entries)

          content.sub(T.must(compat_section_match[0]), "[compat]\n#{new_compat_section}")
        else
          content + "\n[compat]\n#{dependency_name} = \"#{requirement}\"\n"
        end
      end

      sig { params(compat_section: String).returns(T::Hash[String, String]) }
      def parse_compat_entries(compat_section)
        entries = {}
        compat_section.each_line do |line|
          next if line.strip.empty? || line.strip.start_with?("#")

          match = line.match(/^\s*([^=\s]+)\s*=\s*(.+?)(?:\s*#.*)?$/)
          next unless match

          key = T.must(match[1]).strip
          value = T.must(match[2]).strip.gsub(/^["']|["']$/, "")
          entries[key] = value
        end
        entries
      end

      sig { params(entries: T::Hash[String, String]).returns(T::Hash[String, String]) }
      def sort_compat_entries(entries)
        entries.sort.to_h
      end

      sig { params(entries: T::Hash[String, String]).returns(String) }
      def build_compat_section(entries)
        entries.map { |name, requirement| "#{name} = \"#{requirement}\"\n" }.join
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)
