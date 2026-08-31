# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Codeql
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        if qlpack_file && file_changed?(T.must(qlpack_file))
          updated_files << updated_file(
            file: T.must(qlpack_file),
            content: updated_qlpack_content(T.must(qlpack_file))
          )
        end

        if lockfile && lockfile_changed?
          updated_files << updated_file(
            file: T.must(lockfile),
            content: updated_lockfile_content(T.must(lockfile))
          )
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No qlpack.yml file!" unless qlpack_file
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_qlpack_content(file)
        content = T.must(file.content).dup

        dependencies.each do |dependency|
          new_req = dependency.requirements.find { |r| r.file == file.name }
          old_req = dependency.previous_requirements&.find { |r| r.file == file.name }
          next unless new_req && old_req

          new_requirement = new_req.requirement.to_s
          old_requirement = old_req.requirement.to_s
          next if new_requirement == old_requirement

          content = replace_manifest_requirement(
            content: content,
            name: dependency.name,
            old_requirement: old_requirement,
            new_requirement: new_requirement
          )
        end

        content
      end

      sig do
        params(content: String, name: String, old_requirement: String, new_requirement: String).returns(String)
      end
      def replace_manifest_requirement(content:, name:, old_requirement:, new_requirement:)
        pattern = /^(\s*#{Regexp.escape(name)}:\s*)#{Regexp.escape(old_requirement)}(\s*)$/
        content.sub(pattern, "\\1#{new_requirement}\\2")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_lockfile_content(file)
        content = T.must(file.content).dup

        dependencies.each do |dependency|
          new_version = dependency.version
          previous_version = dependency.previous_version
          next unless new_version && previous_version
          next if new_version == previous_version

          content = replace_lockfile_version(
            content: content,
            name: dependency.name,
            new_version: new_version
          )
        end

        content
      end

      sig { params(content: String, name: String, new_version: String).returns(String) }
      def replace_lockfile_version(content:, name:, new_version:)
        pattern = /^(\s*#{Regexp.escape(name)}:\s*\n\s*version:\s*).*$/
        content.sub(pattern, "\\1#{new_version}")
      end

      sig { returns(T::Boolean) }
      def lockfile_changed?
        file = lockfile
        return false unless file

        updated_lockfile_content(file) != file.content
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def qlpack_file
        @qlpack_file ||= T.let(get_original_file("qlpack.yml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("codeql-pack.lock.yml"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileUpdaters.register("codeql", Dependabot::Codeql::FileUpdater)
