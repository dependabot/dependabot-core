# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Hex
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/mixfile_updater"
      require_relative "file_updater/lockfile_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        if Dependabot::Experiments.enabled?(:allowlist_dependency_files)
          [
            /^.*mix\.exs$/,
            /^.*mix\.lock$/
          ]
        else
          # Old regex. After 100% rollout of the allowlist, this will be removed.
          [
            /^mix\.exs$/,
            /^mix\.lock$/
          ]
        end
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        mixfiles.each do |file|
          if file_changed?(file)
            updated_files <<
              updated_file(file: file, content: updated_mixfile_content(file))
          end
        end

        if lockfile
          updated_files <<
            updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No mix.exs!" unless get_original_file("mix.exs")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_mixfile_content(file)
        MixfileUpdater.new(
          dependencies: dependencies,
          mixfile: file
        ).updated_mixfile_content
      end

      sig { returns(String) }
      def updated_lockfile_content
        @updated_lockfile_content ||= T.let(nil, T.nilable(String))
        LockfileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_lockfile_content
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def mixfiles
        dependency_files.select { |f| f.name.end_with?("mix.exs") }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("mix.lock"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileUpdaters.register("hex", Dependabot::Hex::FileUpdater)
