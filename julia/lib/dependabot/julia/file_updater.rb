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
          # Update all project files (main + workspace members)
          updated_project_files = update_all_project_files
          actual_manifest = find_manifest_file

          return all_projects_only_update(updated_project_files) if actual_manifest.nil?

          # Requirement-only updates (no target versions) have nothing to tell
          # Pkg; ship the Project.toml changes on their own.
          return all_projects_only_update(updated_project_files) if build_updates_hash.empty?

          # Write all updated project files to disk for Julia's Pkg
          write_all_temporary_files(updated_project_files, actual_manifest)
          result = call_julia_helper

          return handle_julia_helper_error_multi(result, actual_manifest, updated_project_files) if result["error"]

          build_updated_files_multi(updated_files, updated_project_files, actual_manifest, result)
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def update_all_project_files
        all_project_files.map do |proj_file|
          {
            file: proj_file,
            content: updated_project_content_for_file(proj_file)
          }
        end
      end

      sig { params(proj_file: Dependabot::DependencyFile).returns(String) }
      def updated_project_content_for_file(proj_file)
        content = T.must(proj_file.content)

        dependencies.each do |dependency|
          # Find the new requirement for this dependency in this file
          new_requirement = dependency.requirements
                                      .find { |req| T.cast(req[:file], String) == proj_file.name }
                                      &.fetch(:requirement)

          next unless new_requirement

          content = update_dependency_requirement_in_content(content, dependency.name, new_requirement)
        end

        content
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def all_project_files
        dependency_files.select { |f| f.name.match?(/Project\.toml$/i) }
      end

      sig { params(updated_project_files: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Dependabot::DependencyFile]) }
      def all_projects_only_update(updated_project_files)
        updated_project_files.filter_map do |update_info|
          file = T.cast(update_info[:file], Dependabot::DependencyFile)
          content = T.cast(update_info[:content], String)
          next if content == file.content

          updated_file(file: file, content: content)
        end
      end

      sig do
        params(
          updated_project_files: T::Array[T::Hash[Symbol, T.untyped]],
          actual_manifest: Dependabot::DependencyFile
        ).void
      end
      def write_all_temporary_files(updated_project_files, actual_manifest)
        # Write all updated project files
        updated_project_files.each do |update_info|
          file = T.cast(update_info[:file], Dependabot::DependencyFile)
          content = T.cast(update_info[:content], String)

          file_path = file.name
          FileUtils.mkdir_p(File.dirname(file_path)) if file_path.include?("/")
          File.write(file_path, content)
        end

        # Write manifest file
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
          updated_project_files: T::Array[T::Hash[Symbol, T.untyped]]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def handle_julia_helper_error_multi(result, actual_manifest, updated_project_files)
        error_message = result["error"]
        manifest_path = actual_manifest.name

        is_resolver_error = resolver_error?(error_message)
        raise error_message unless is_resolver_error

        add_manifest_update_notice(manifest_path, error_message)

        # Return all updated Project.toml files
        all_projects_only_update(updated_project_files)
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
          updated_project_files: T::Array[T::Hash[Symbol, T.untyped]],
          actual_manifest: Dependabot::DependencyFile,
          result: T::Hash[String, T.untyped]
        ).void
      end
      def build_updated_files_multi(updated_files, updated_project_files, actual_manifest, result)
        # Add all updated project files
        updated_project_files.each do |update_info|
          file = T.cast(update_info[:file], Dependabot::DependencyFile)
          content = T.cast(update_info[:content], String)
          next if content == file.content

          updated_files << updated_file(file: file, content: content)
        end

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

      sig { returns(T::Hash[String, T::Hash[String, String]]) }
      def build_updates_hash
        @build_updates_hash ||= T.let(
          begin
            updates = T.let({}, T::Hash[String, T::Hash[String, String]])
            dependencies.each do |dependency|
              version = dependency.version
              next unless version

              uuid = dependency.metadata[:julia_uuid]
              unless uuid.is_a?(String)
                Dependabot.logger.warn("Skipping manifest update for #{dependency.name}: no UUID available")
                next
              end

              updates[uuid] = {
                "name" => dependency.name,
                "version" => version
              }
            end
            updates
          end,
          T.nilable(T::Hash[String, T::Hash[String, String]])
        )
      end

      # Helper methods for DependabotHelper.jl integration

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Julia::RegistryClient.new(
            credentials: credentials,
            custom_registries: custom_registries
          ),
          T.nilable(Dependabot::Julia::RegistryClient)
        )
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def custom_registries
        @custom_registries ||= T.let(
          begin
            registries_config = T.cast(options[:registries], T.nilable(T::Hash[Symbol, T.anything]))
            registries = T.cast(registries_config&.dig(:julia), T.nilable(T::Array[T::Hash[Symbol, T.anything]])) || []
            registries.map { |registry| registry.transform_keys(&:to_sym) }
          end,
          T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
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
          is_manifest && (f.directory == project_dir || parent_directory_of?(f.directory, project_dir))
        end
      end

      sig { params(candidate: String, dir: String).returns(T::Boolean) }
      def parent_directory_of?(candidate, dir)
        # Segment-aware prefix check so "/doc" is not treated as a parent of "/docs"
        prefix = candidate.end_with?("/") ? candidate : "#{candidate}/"
        dir.start_with?(prefix)
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
          next unless File.basename(f.name).match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)

          # Construct the full path for this file, resolving ".." segments
          # (workspace manifests are named e.g. "../Manifest.toml")
          file_path = Pathname.new(File.join(f.directory, f.name)).cleanpath.to_s.sub(%r{^/}, "")
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

      # Matches a [compat] table header, tolerating indentation and a trailing
      # comment ("[compat]  # pins")
      COMPAT_HEADER_PATTERN = T.let(/^\s*\[compat\]\s*(?:#.*)?$/, Regexp)

      sig { params(content: String, dependency_name: String, new_requirement: String).returns(String) }
      def update_dependency_requirement_in_content(content, dependency_name, new_requirement)
        lines = content.lines
        header_idx = lines.index { |line| line.match?(COMPAT_HEADER_PATTERN) }

        unless header_idx
          # Add a new [compat] section at the end of the file
          separator = content.end_with?("\n") ? "" : "\n"
          return "#{content}#{separator}\n[compat]\n#{dependency_name} = \"#{new_requirement}\"\n"
        end

        section_end = ((header_idx + 1)...lines.length).find { |i| T.must(lines[i]).match?(/^\s*\[/) } ||
                      lines.length

        # Replace an existing entry in place, preserving surrounding lines
        entry_pattern =
          /^(\s*#{Regexp.escape(dependency_name)}\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s#\n]+)(\s*(?:\#.*)?)$/
        ((header_idx + 1)...section_end).each do |i|
          line = T.must(lines[i])
          next unless line.match?(entry_pattern)

          lines[i] = line.sub(entry_pattern) { "#{Regexp.last_match(1)}\"#{new_requirement}\"#{Regexp.last_match(2)}" }
          return lines.join
        end

        insert_compat_entry(lines, header_idx, section_end, dependency_name, new_requirement)
      end

      # Insert a new compat entry in alphabetical position without rewriting
      # the rest of the section, so comments, blank lines and any custom
      # ordering of the existing entries survive.
      sig do
        params(
          lines: T::Array[String],
          header_idx: Integer,
          section_end: Integer,
          dependency_name: String,
          requirement: String
        ).returns(String)
      end
      def insert_compat_entry(lines, header_idx, section_end, dependency_name, requirement)
        insert_at = T.let(nil, T.nilable(Integer))

        ((header_idx + 1)...section_end).each do |i|
          key = T.must(lines[i])[/^\s*([^#\s=][^=\s]*)\s*=/, 1]
          next unless key && key > dependency_name

          insert_at = i
          # Comment lines directly above an entry belong to it
          insert_at -= 1 while insert_at > header_idx + 1 && T.must(lines[insert_at - 1]).strip.start_with?("#")
          break
        end

        unless insert_at
          # Append at the end of the section, before any trailing blank lines
          insert_at = section_end
          insert_at -= 1 while insert_at > header_idx + 1 && T.must(lines[insert_at - 1]).strip.empty?
        end

        # The preceding line may lack a newline when the section ends the file
        prev = lines[insert_at - 1]
        lines[insert_at - 1] = "#{prev}\n" if prev && !prev.end_with?("\n")

        lines.insert(insert_at, "#{dependency_name} = \"#{requirement}\"\n")
        lines.join
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)
