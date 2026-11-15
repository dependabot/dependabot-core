# typed: strong
# frozen_string_literal: true

require "json"
require "toml-rb"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"
require "dependabot/mise/version"
require "dependabot/shared_helpers"

module Dependabot
  module Mise
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      class LockTarget < T::Struct
        const :file, String
        const :tool, String
        const :version, T.nilable(String)
        const :changed, T::Boolean
        const :lockfile_only, T::Boolean
      end

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
          targets = lock_targets(manifests.map(&:name))
          next if lockfile.nil? || targets.none?(&:changed)

          lock_changes(lockfile, manifests, targets, files.values).each do |path, content|
            change = changed_file(path, content, lockfile.directory)
            changes[path] = change
            if change.nil? || change.deleted?
              files.delete(path)
              next
            end

            files[path] = change
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

      # Unchanged manifests declaring an updated tool are included, so the version check covers them too.
      sig { params(file_names: T::Array[String]).returns(T::Array[LockTarget]) }
      def lock_targets(file_names)
        targets = dependencies.map { |dep| file_names.filter_map { |file_name| lock_target(dep, file_name) } }
        targets.select { |dep_targets| dep_targets.any?(&:changed) }.flatten
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(T.nilable(LockTarget)) }
      def lock_target(dep, file_name)
        req = requirement_for(dep.requirements, file_name)
        return unless req

        previous = previous_requirement_for(dep, file_name)
        version = req.metadata_string("resolved_version") || req.requirement_string
        LockTarget.new(
          file: file_name,
          tool: dep.name,
          version: Dependabot::Mise::Version.correct?(version) ? version : nil,
          changed: req != previous,
          lockfile_only: req != previous && req.requirement_string == previous&.requirement_string
        )
      end

      sig do
        params(requirements: T::Array[Dependabot::DependencyRequirement], file_name: String)
          .returns(T.nilable(Dependabot::DependencyRequirement))
      end
      def requirement_for(requirements, file_name)
        requirements.find { |req| req.file == file_name }
      end

      sig do
        params(dep: Dependabot::Dependency, file_name: String).returns(T.nilable(Dependabot::DependencyRequirement))
      end
      def previous_requirement_for(dep, file_name)
        requirement_for(dep.previous_requirements || [], file_name)
      end

      # Every manifest sharing the lockfile is loaded, or mise drops the versions the others pin.
      sig do
        params(
          lockfile: Dependabot::DependencyFile,
          manifests: T::Array[Dependabot::DependencyFile],
          targets: T::Array[LockTarget],
          files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Hash[String, T.nilable(String)])
      end
      def lock_changes(lockfile, manifests, targets, files)
        old_sidecars = Dependabot::Mise::FileFetcher.sidecar_dirs(lockfile.name, lockfile.content.to_s)
        sidecar_files = files.select { |file| inside?(file.name, old_sidecars) }
        shared_sidecars = sidecar_dirs_of_other_lockfiles(files, lockfile.name)

        Dependabot::SharedHelpers.in_a_temporary_directory do
          write_manifest_files(manifests + [lockfile] + sidecar_files)
          changes = changes_made_by { run_mise_lock(manifests, targets) }
          check_only_lock_files_changed(changes, lockfile, old_sidecars)
          check_locked_versions(targets)

          changes.reject { |path, content| content.nil? && inside?(path, shared_sidecars) }
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed, JSON::ParserError => e
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

      sig { params(targets: T::Array[LockTarget]).void }
      def check_locked_versions(targets)
        targets.each do |target|
          next unless target.version

          entries = T.cast(JSON.parse(mise_ls(target.file, target.tool)), Object)
          entry = T.let(entries.is_a?(Array) ? entries.first : nil, Object)
          locked = T.let(entry.is_a?(Hash) ? entry["version"] : nil, Object)
          next if locked == target.version

          raise Dependabot::DependencyFileNotResolvable,
                "mise resolves #{target.tool} in #{target.file} to #{locked || 'nothing'}, not #{target.version}"
        end
      end

      sig { params(manifests: T::Array[Dependabot::DependencyFile], targets: T::Array[LockTarget]).void }
      def run_mise_lock(manifests, targets)
        bump = targets.any?(&:lockfile_only) ? ["--bump"] : []
        tools = targets.select(&:changed).map(&:tool).uniq
        Dependabot::SharedHelpers.run_shell_command(
          ["mise", "lock", *bump, "--", *tools],
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
        deps_for_file = dependencies.select { |dep| requirement_for(dep.requirements, file_name) }

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
        previous_requirement_for(dep, file_name)&.requirement_string || dep.previous_version.to_s
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(String) }
      def new_version_string_for(dep, file_name)
        requirement_for(dep.requirements, file_name)&.requirement_string || dep.version.to_s
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
