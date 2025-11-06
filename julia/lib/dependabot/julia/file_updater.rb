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

        Dependabot.logger.info("FileUpdater: Starting update for #{dependencies.map(&:name).join(', ')}")
        Dependabot.logger.info("FileUpdater: Available dependency files: #{dependency_files.map { |f| "#{f.directory}/#{f.name}" }.join(', ')}")

        SharedHelpers.in_a_temporary_repo_directory(project_directory, repo_contents_path) do
          updated_project = updated_project_content

          actual_manifest = find_manifest_file
          Dependabot.logger.info("FileUpdater: Found manifest: #{actual_manifest ? "#{actual_manifest.directory}/#{actual_manifest.name}" : "nil"}")

          return project_only_update(updated_project) if actual_manifest.nil?

          # For workspace packages, we need to update ALL Project.toml files that share
          # the same Manifest.toml BEFORE calling the Julia helper. Otherwise the resolver
          # will fail because some compat entries are updated and others aren't.
          other_updated_projects = update_workspace_sibling_projects(actual_manifest)
          Dependabot.logger.info("FileUpdater: Updated #{other_updated_projects.length} sibling projects")

          write_temporary_files(updated_project, actual_manifest)
          result = call_julia_helper
          $stderr.puts "actual_manifest.content length: #{T.must(actual_manifest.content).length}"
          if result['manifest_content']
            $stderr.puts "result manifest_content length: #{result['manifest_content'].length}"
            $stderr.puts "Content changed: #{result['manifest_content'] != actual_manifest.content}"
          end
          $stderr.puts "=========================================\n"

          return handle_julia_helper_error(result, actual_manifest, updated_project) if result["error"]

          build_updated_files(updated_files, updated_project, actual_manifest, result, other_updated_projects)
          Dependabot.logger.info("FileUpdater: Built #{updated_files.length} updated files: #{updated_files.map { |f| "#{f.directory}/#{f.name}" }.join(', ')}")
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

        manifest_relative_path = relative_path_from_project(actual_manifest)
        ensure_relative_directory(manifest_relative_path)
        File.write(manifest_relative_path, T.must(actual_manifest.content))
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
          result: T::Hash[String, T.untyped],
          other_updated_projects: T::Hash[Dependabot::DependencyFile, String]
        ).void
      end
      def build_updated_files(updated_files, updated_project, actual_manifest, result, other_updated_projects)
        updated_files << updated_file(file: T.must(project_file), content: updated_project)

        # Add any other workspace Project.toml files that were updated
        other_updated_projects.each do |project_file_obj, updated_content|
          updated_files << updated_file(file: project_file_obj, content: updated_content)
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

      # Update other Project.toml files in the workspace that share the same Manifest.toml
      # Returns a hash mapping DependencyFile objects to their updated content
      sig { params(manifest: Dependabot::DependencyFile).returns(T::Hash[Dependabot::DependencyFile, String]) }
      def update_workspace_sibling_projects(manifest)
        updated_projects = {}

        Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects: Looking for siblings of #{project_file&.path}")
        Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects: Manifest is #{manifest.directory}/#{manifest.name}")
        Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects: Available files: #{dependency_files.map { |f| "#{f.directory}/#{f.name}" }.join(', ')}")

        # Find other Project.toml files that share this manifest
        dependency_files.each do |file|
          next unless file.name.match?(/^(Julia)?Project\.toml$/i)

          is_current = file == project_file
          Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects:   Checking #{file.directory}/#{file.name}: is_current=#{is_current}")
          next if is_current # Skip the current project

          # Check if this project shares the same manifest by comparing directories
          # For workspace packages, they're typically siblings under the same parent
          file_manifest = find_manifest_for_project(file)
          manifest_matches = file_manifest && file_manifest.name == manifest.name && file_manifest.directory == manifest.directory
          Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects:     file_manifest=#{file_manifest ? "#{file_manifest.directory}/#{file_manifest.name}" : "nil"}, matches=#{manifest_matches}")
          next unless manifest_matches

          # Update this project file with the same dependency updates
          updated_content = update_project_content_for_file(file)
          content_changed = updated_content != file.content
          Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects:     content_changed=#{content_changed}")
          next if updated_content == file.content

          # Write the updated content to disk so Julia helper can see it
          sibling_relative_path = relative_path_from_project(file)
          ensure_relative_directory(sibling_relative_path)
          File.write(sibling_relative_path, updated_content)

          updated_projects[file] = updated_content
        end

        Dependabot.logger.info("FileUpdater.update_workspace_sibling_projects: Found #{updated_projects.length} siblings to update")
        updated_projects
      end

      # Find the manifest file that would be used by a given project file
      sig { params(project: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def find_manifest_for_project(project)
        # Look for Manifest.toml in the same directory or parent directories
        current_dir = project.directory

        # Check same directory first
        manifest = dependency_files.find do |f|
          f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i) && f.directory == current_dir
        end
        return manifest if manifest

        # Check parent directory (common for workspace packages)
        parent_dir = File.dirname(current_dir)
        dependency_files.find do |f|
          f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i) && f.directory == parent_dir
        end
      end

      # Update a project file's content with the same dependency updates
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def update_project_content_for_file(file)
        content = T.must(file.content)
        file_path = file.path.sub(%r{^/}, "")

        Dependabot.logger.info("FileUpdater.update_project_content_for_file: Updating #{file_path}")

        dependencies.each do |dependency|
          unless dependency_declared_in_dependency_sections?(file, dependency.name)
            Dependabot.logger.info(
              "FileUpdater.update_project_content_for_file:   #{dependency.name}: not declared in deps/extras/weakdeps, skipping"
            )
            next
          end

          # Find the new requirement for this dependency
          # Compare with the full file path since requirements now use full paths
          new_requirement = dependency.requirements
                                      .find { |req| T.cast(req[:file], String) == file_path }
                                      &.fetch(:requirement)
          new_requirement ||= shared_requirement_for_dependency(dependency)

          Dependabot.logger.info("FileUpdater.update_project_content_for_file:   #{dependency.name}: requirement=#{new_requirement.inspect}")
          next unless new_requirement

          content = update_dependency_requirement_in_content(content, dependency.name, new_requirement)
        end

        content
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

        Dependabot.logger.info("FileUpdater.find_manifest_file: Looking for manifest for project_dir=#{project_dir}")
        Dependabot.logger.info("FileUpdater.find_manifest_file: Available files: #{dependency_files.map { |f| "#{f.directory}/#{f.name} (shared=#{f.shared_across_directories?})" }.join(', ')}")

        result = dependency_files.find do |f|
          # Use basename to get just the filename, not the full path with ../
          is_manifest = File.basename(f.name).match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)
          # For workspace packages, manifest can be in parent directory
          # Check if file directory matches exactly or if project_dir is a subdirectory of file directory
          matches_dir = f.directory == project_dir || project_dir.start_with?("#{f.directory}/")
          Dependabot.logger.info("FileUpdater.find_manifest_file:   Checking #{f.directory}/#{f.name}: is_manifest=#{is_manifest}, matches_dir=#{matches_dir}")
          is_manifest && matches_dir
        end

        Dependabot.logger.info("FileUpdater.find_manifest_file: Result: #{result ? "#{result.directory}/#{result.name}" : 'nil'}")
        result
      end

      sig { params(manifest_path: String).returns(Dependabot::DependencyFile) }
      def manifest_file_for_path(manifest_path)
        # manifest_path is relative to the project directory (e.g., "Manifest.toml" or "../Manifest.toml")
        # Resolve it to a canonical repo-relative path and return a DependencyFile that
        # references the canonical location (no relative components like "..").
        # This ensures FileUpdater instances for different subpackages return the same
        # file identity and allows the updater service to deduplicate correctly.

        project_dir = T.must(project_file).directory

        # Resolve the manifest path to an absolute repo-relative path
        absolute_path = Pathname.new(File.join(project_dir, manifest_path)).cleanpath.to_s
        repo_relative_path = absolute_path.sub(%r{^/}, "")

        # Try to find an existing DependencyFile that matches the resolved path
        found_manifest = dependency_files.find do |f|
          next unless f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)

          file_full_path = File.join(f.directory, f.name).sub(%r{^/}, "")
          file_full_path == repo_relative_path
        end

        if found_manifest
          # Return a normalized DependencyFile that uses the manifest's actual directory
          # and preserves any metadata (like associated manifest paths) so the updater
          # service continues treating the file as shared across directories.
          Dependabot::DependencyFile.new(
            name: File.basename(found_manifest.name),
            content: found_manifest.content,
            directory: found_manifest.directory,
            type: found_manifest.type,
            support_file: found_manifest.support_file?,
            vendored_file: found_manifest.vendored_file?,
            symlink_target: found_manifest.symlink_target,
            content_encoding: found_manifest.content_encoding,
            operation: found_manifest.operation,
            mode: found_manifest.mode,
            associated_manifest_paths: found_manifest.associated_manifest_paths,
            associated_lockfile_path: found_manifest.associated_lockfile_path
          )
        else
          # If we couldn't find it, create a canonical DependencyFile using the
          # resolved repo-relative path components.
          canonical_dir = "/" + File.dirname(repo_relative_path)
          Dependabot::DependencyFile.new(
            name: File.basename(repo_relative_path),
            content: "",
            directory: canonical_dir
          )
        end
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
          begin
            project_files = dependency_files.select { |file| file.name.match?(/^(Julia)?Project\.toml$/i) }
            project_files.find do |file|
              directory_targets.include?(Pathname.new(file.directory).cleanpath.to_s) ||
                requirement_targets.include?(file.path.sub(%r{^/}, ""))
            end || project_files.first
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def updated_project_content
        return T.must(T.must(project_file).content) unless project_file

        content = T.must(T.must(project_file).content)
        project_requirement_path = T.must(project_file).path.sub(%r{^/}, "")
        project_requirement_name = T.must(project_file).name

        dependencies.each do |dependency|
          # Find the new requirement for this dependency
          new_requirement = dependency.requirements
                                      .find do |req|
                                        req_file = T.cast(req[:file], String)
                                        req_file == project_requirement_path || req_file == project_requirement_name
                                      end
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
        # Find [compat] section or create it
        if content.match?(/^\s*\[compat\]\s*$/m)
          # Add to existing [compat] section
          content.gsub(/(\[compat\]\s*\n)/, "\\1#{dependency_name} = \"#{requirement}\"\n")
        else
          # Add new [compat] section at the end
          content + "\n[compat]\n#{dependency_name} = \"#{requirement}\"\n"
        end
      end

      sig { returns(String) }
      def project_directory
        T.must(project_file).directory
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def relative_path_from_project(file)
        project_path = Pathname.new(project_directory)
        file_path = Pathname.new(File.join(file.directory, file.name)).cleanpath
        file_path.relative_path_from(project_path).to_path
      end

      sig { params(path: String).void }
      def ensure_relative_directory(path)
        dir = File.dirname(path)
        return if dir == "." || dir.start_with?("..")

        FileUtils.mkdir_p(dir)
      end

      sig { returns(T::Array[String]) }
      def directory_targets
        @directory_targets ||= T.let(
          dependencies.filter_map do |dependency|
            directory = dependency.metadata[:directory]
            next unless directory

            Pathname.new(directory).cleanpath.to_s
          end.uniq,
          T.nilable(T::Array[String])
        )
      end

      sig { returns(T::Array[String]) }
      def requirement_targets
        @requirement_targets ||= T.let(
          dependencies.flat_map do |dependency|
            dependency.requirements.filter_map do |req|
              file = req[:file]
              next unless file

              file.sub(%r{^/}, "")
            end
          end.uniq,
          T.nilable(T::Array[String])
        )
      end

      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
      def shared_requirement_for_dependency(dependency)
        unique_requirements = dependency.requirements.filter_map { |req| req[:requirement] }.uniq
        return nil unless unique_requirements.one?

        unique_requirements.first
      end

      sig { params(file: Dependabot::DependencyFile, dependency_name: String).returns(T::Boolean) }
      def dependency_declared_in_dependency_sections?(file, dependency_name)
        content = T.must(file.content)
        parsed = TomlRB.parse(content)
        sections = ["deps", "extras", "weakdeps"]

        sections.any? do |section|
          table = parsed[section]
          next false unless table.is_a?(Hash)

          table.key?(dependency_name)
        end
      rescue TomlRB::ParseError => e
        Dependabot.logger.warn(
          "FileUpdater: Failed to parse #{file.path} while checking dependency declarations: #{e.message}"
        )
        true
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)
