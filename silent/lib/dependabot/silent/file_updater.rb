# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "sorbet-runtime"

module SilentPackageManager
  class FileUpdater < Dependabot::FileUpdaters::Base
    extend T::Sig

    sig { override.returns(T::Array[Dependabot::DependencyFile]) }
    def updated_dependency_files
      return [] if dependency&.name == "dont-update-any-files"

      updated_files = []
      dependency_files.each do |file|
        next unless requirement_changed?(file, T.must(dependency))

        updated_files << updated_file(file: file, content: updated_file_content(file))
      end

      updated_files.reject! { |f| dependency_files.include?(f) }
      raise "No files changed!" if updated_files.none?

      updated_files
    end

    private

    sig { returns(T.nilable(Dependabot::Dependency)) }
    def dependency
      # Dockerfiles will only ever be updating a single dependency
      dependencies.first
    end

    sig { override.void }
    def check_required_files
      # Just check if there are any files at all.
      return if dependency_files.any?

      raise "No dependency files!"
    end

    sig { params(file: Dependabot::DependencyFile).returns(String) }
    def updated_file_content(file)
      original_content = JSON.parse(T.must(file.content))
      original_content.each do |name, info|
        next unless name == T.must(dependency).name

        # If this was a multi-version update, assume we've updated all versions to be the same.
        info.delete("versions") if info["versions"]

        info["version"] = requirements(file).first&.fetch(:requirement)
        if info["depends-on"]
          # also bump dependants to the same version
          original_content[info["depends-on"]]["version"] = requirements(file).first&.fetch(:requirement)
        end
      end
      c = JSON.pretty_generate(original_content)
      puts c
      c
    end

    sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, String]]) }
    def requirements(file)
      dependency&.requirements&.filter { |r| r[:file] == file.name } || []
    end

    sig { params(file: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
    def previous_requirements(file)
      dependency&.previous_requirements&.filter { |r| r[:file] == file.name } || []
    end
  end
end

Dependabot::FileUpdaters.register("silent", SilentPackageManager::FileUpdater)
