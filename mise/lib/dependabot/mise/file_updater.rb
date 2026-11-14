# typed: strong
# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Mise
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        files_to_update = dependencies.flat_map do |dep|
          dep.requirements.map(&:file)
        end.uniq

        files_to_update.each do |file_name|
          mise_file = dependency_files.find { |f| f.name == file_name }
          next unless mise_file

          new_content = updated_mise_toml_content(mise_file.content.to_s, mise_file.name)
          updated_files << updated_file(file: mise_file, content: new_content) if new_content != mise_file.content
        end

        updated_files + updated_lockfiles(updated_files)
      end

      private

      # Lockfiles are relocked one at a time, each seeing the files earlier ones changed,
      # because two lockfiles can share a sidecar directory.
      sig do
        params(updated_manifests: T::Array[Dependabot::DependencyFile])
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def updated_lockfiles(updated_manifests)
        files = (dependency_files + updated_manifests).to_h { |file| [file.name, file] }
        changes = T.let({}, T::Hash[String, T.nilable(Dependabot::DependencyFile)])

        manifest_groups(files.values).each do |lockfile_name, manifests|
          lockfile = files[lockfile_name]
          tools = tools_updated_in(manifests.map(&:name) & updated_manifests.map(&:name))
          next if lockfile.nil? || tools.empty?

          lock_changes(lockfile, manifests, tools, files.values).each do |path, content|
            change = changes[path] = changed_file(path, content, lockfile.directory)
            change.nil? || change.deleted? ? files.delete(path) : files[path] = change
          end
        end
        changes.values.compact
      end

      sig do
        params(files: T::Array[Dependabot::DependencyFile])
          .returns(T::Hash[String, T::Array[Dependabot::DependencyFile]])
      end
      def manifest_groups(files)
        files.select { |file| Dependabot::Mise::FileFetcher.mise_config_file?(file.name) }
             .group_by { |file| Dependabot::Mise::FileFetcher.lockfile_path_for(file.name) }
      end

      sig { params(file_names: T::Array[String]).returns(T::Array[String]) }
      def tools_updated_in(file_names)
        dependencies.select do |dep|
          file_names.any? do |file_name|
            dep.requirements.any? { |req| req.file == file_name } &&
              requested_version_for(dep, file_name) != new_version_string_for(dep, file_name)
          end
        end.map(&:name).uniq
      end

      # Every manifest sharing the lockfile is loaded, or mise drops the versions the others pin.
      sig do
        params(
          lockfile: Dependabot::DependencyFile,
          manifests: T::Array[Dependabot::DependencyFile],
          tools: T::Array[String],
          files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Hash[String, T.nilable(String)])
      end
      def lock_changes(lockfile, manifests, tools, files)
        old_sidecars = Dependabot::Mise::FileFetcher.sidecar_dirs(lockfile.name, lockfile.content.to_s)
        sidecar_files = files.select { |file| inside?(file.name, old_sidecars) }
        shared_sidecars = sidecar_dirs_of_other_lockfiles(files, lockfile.name)

        Dependabot::SharedHelpers.in_a_temporary_directory do
          write_manifest_files(manifests + [lockfile] + sidecar_files)
          changes = changes_made_by { run_mise_lock(manifests, tools) }
          check_only_lock_files_changed(changes, lockfile, old_sidecars)

          changes.reject { |path, content| content.nil? && inside?(path, shared_sidecars) }
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        raise Dependabot::DependencyFileNotResolvable, e.message
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(lockfile.name, e.message)
      end

      sig { params(files: T::Array[Dependabot::DependencyFile], lockfile_name: String).returns(T::Array[String]) }
      def sidecar_dirs_of_other_lockfiles(files, lockfile_name)
        other_names = manifest_groups(files).keys - [lockfile_name]
        files.select { |file| other_names.include?(file.name) }
             .flat_map { |file| Dependabot::Mise::FileFetcher.sidecar_dirs(file.name, file.content.to_s) }
      end

      sig do
        params(
          changes: T::Hash[String, T.nilable(String)],
          lockfile: Dependabot::DependencyFile,
          old_sidecars: T::Array[String]
        ).void
      end
      def check_only_lock_files_changed(changes, lockfile, old_sidecars)
        new_lockfile = changes.fetch(lockfile.name, lockfile.content).to_s
        sidecars = old_sidecars | Dependabot::Mise::FileFetcher.sidecar_dirs(lockfile.name, new_lockfile)
        unexpected = changes.keys.reject { |path| path == lockfile.name || inside?(path, sidecars) }
        return if unexpected.empty?

        raise Dependabot::DependencyFileNotResolvable,
              "mise lock changed files Dependabot doesn't manage: #{unexpected.join(', ')}"
      end

      sig { params(path: String, dirs: T::Array[String]).returns(T::Boolean) }
      def inside?(path, dirs)
        dirs.any? { |dir| path.start_with?("#{dir}/") }
      end

      sig { params(manifests: T::Array[Dependabot::DependencyFile], tools: T::Array[String]).void }
      def run_mise_lock(manifests, tools)
        Dependabot::SharedHelpers.run_shell_command(
          ["mise", "lock", "--", *tools],
          stderr_to_stdout: false,
          env: {
            "MISE_YES" => "1",
            "MISE_SAFE" => "1",
            "MISE_OVERRIDE_CONFIG_FILENAMES" => manifests.map(&:name).join(":")
          }
        )
      end

      # Compared with the original files, so a file created and then deleted by another lockfile drops out.
      sig do
        params(path: String, content: T.nilable(String), directory: String)
          .returns(T.nilable(Dependabot::DependencyFile))
      end
      def changed_file(path, content, directory)
        original = dependency_files.find { |file| file.name == path }
        if original && content
          updated_file(file: original, content: content)
        elsif original
          Dependabot::DependencyFile.new(
            name: path, content: nil, directory: original.directory, operation: Dependabot::DependencyFile::Operation::DELETE
          )
        elsif content
          Dependabot::DependencyFile.new(
            name: path, content: content, directory: directory, operation: Dependabot::DependencyFile::Operation::CREATE
          )
        end
      end

      sig { params(block: T.proc.void).returns(T::Hash[String, T.nilable(String)]) }
      def changes_made_by(&block)
        before = working_directory_contents
        yield
        after = working_directory_contents

        (before.keys | after.keys).reject { |path| before[path] == after[path] }.to_h { |path| [path, after[path]] }
      end

      sig { returns(T::Hash[String, String]) }
      def working_directory_contents
        Dir.glob("**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path, File.read(path)] }
      end

      sig { params(content: String, file_name: String).returns(String) }
      def updated_mise_toml_content(content, file_name)
        deps_for_file = dependencies.select do |dep|
          dep.requirements.any? { |r| r.file == file_name }
        end

        deps_for_file.each_with_object(content.dup) do |dep, updated_content|
          next if requested_version_for(dep, file_name) == new_version_string_for(dep, file_name)

          new_content = update_dependency(updated_content, dep, file_name)
          if new_content == updated_content
            raise no_files_changed_error(
              "Expected content to change for #{dep.name} in #{file_name}!",
              dependency_name: dep.name,
              dependency_file: file_name
            )
          end

          updated_content.replace(new_content)
        end
      end

      # Accept a text replacement only if it updates the parsed tool version.
      sig { params(content: String, dep: Dependabot::Dependency, file_name: String).returns(String) }
      def update_dependency(content, dep, file_name)
        old_version = requested_version_for(dep, file_name)
        new_version = new_version_string_for(dep, file_name)
        # An already-updated tool could otherwise validate an unrelated edit.
        return content unless declared_version(content, dep.name) == old_version

        offset = 0
        while (index = content.index(old_version, offset))
          candidate = content.dup
          candidate[index, old_version.length] = new_version
          return candidate if candidate_version(candidate, dep.name) == new_version

          offset = index + 1
        end

        content
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(file_name, e.message)
      end

      # Version arrays and arrays of tables are not managed, so they return nil.
      sig { params(content: String, tool: String).returns(T.nilable(String)) }
      def declared_version(content, tool)
        tools = T.cast(TomlRB.parse(content), T::Hash[String, Object])["tools"]
        return unless tools.is_a?(Hash)

        value = T.let(tools[tool], Object)
        value = T.let(value["version"], Object) if value.is_a?(Hash)
        value if value.is_a?(String)
      end

      sig { params(content: String, tool: String).returns(T.nilable(String)) }
      def candidate_version(content, tool)
        declared_version(content, tool)
      rescue TomlRB::Error
        nil
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(String) }
      def requested_version_for(dep, file_name)
        requirement = T.must(dep.previous_requirements)
                       .find { |r| r.file == file_name }

        requirement&.requirement_string || dep.previous_version.to_s
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(String) }
      def new_version_string_for(dep, file_name)
        requirement = dep.requirements.find { |r| r.file == file_name }

        requirement&.requirement_string || dep.version.to_s
      end

      sig { override.void }
      def check_required_files
        mise_files = dependency_files.select { |f| Dependabot::Mise::FileFetcher.mise_config_file?(f.name) }
        return unless mise_files.empty?

        raise "No mise configuration file found!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("mise", Dependabot::Mise::FileUpdater)
