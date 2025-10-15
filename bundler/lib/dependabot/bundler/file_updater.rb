# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module Bundler
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/gemfile_updater"
      require_relative "file_updater/gemspec_updater"
      require_relative "file_updater/lockfile_updater"

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        if gemfile && file_changed?(T.must(gemfile))
          updated_files <<
            updated_file(
              file: T.must(gemfile),
              content: updated_gemfile_content(T.must(gemfile))
            )
        end

        if lockfile && dependencies.any?(&:appears_in_lockfile?)
          updated_files <<
            updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        top_level_gemspecs.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(file: file, content: updated_gemspec_content(file))
        end

        evaled_gemfiles.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(file: file, content: updated_gemfile_content(file))
        end

        check_updated_files(updated_files)

        base_dir = T.must(updated_files.first).directory
        vendor_updater
          .updated_files(base_directory: base_dir)
          .each do |file|
          updated_files << file
        end

        updated_files
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize

      private

      # Dynamically fetch the vendor cache folder from bundler
      sig { returns(T.nilable(String)) }
      def vendor_cache_dir
        @vendor_cache_dir = T.let(
          NativeHelpers.run_bundler_subprocess(
            bundler_version: bundler_version,
            function: "vendor_cache_dir",
            options: options,
            args: {
              dir: repo_contents_path
            }
          ),
          T.nilable(String)
        )
      end

      sig { returns(Dependabot::FileUpdaters::VendorUpdater) }
      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_cache_dir
        )
      end

      sig { override.void }
      def check_required_files
        file_names = dependency_files.map(&:name)

        raise "A Gemfile must be provided if a lockfile is!" if lockfile && !gemfile

        return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
      end

      sig { params(updated_files: T::Array[Dependabot::DependencyFile]).void }
      def check_updated_files(updated_files)
        return if updated_files.reject { |f| dependency_files.include?(f) }.any?

        raise "No files have changed!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def gemfile
        @gemfile ||= T.let(
          get_original_file("Gemfile") || get_original_file("gems.rb"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          get_original_file("Gemfile.lock") || get_original_file("gems.locked"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def evaled_gemfiles
        @evaled_gemfiles ||= T.let(
          dependency_files
          .reject { |f| f.name.end_with?(".gemspec") }
          .reject { |f| f.name.end_with?(".specification") }
          .reject { |f| f.name.end_with?(".lock") }
          .reject { |f| f.name == "Gemfile" }
          .reject { |f| f.name == "gems.rb" }
          .reject { |f| f.name == "gems.locked" }
          .reject(&:support_file?),
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_gemfile_content(file)
        GemfileUpdater.new(
          dependencies: dependencies,
          gemfile: file
        ).updated_gemfile_content
      end

      sig { params(gemspec: Dependabot::DependencyFile).returns(String) }
      def updated_gemspec_content(gemspec)
        GemspecUpdater.new(
          dependencies: dependencies,
          gemspec: gemspec
        ).updated_gemspec_content
      end

      sig { returns(String) }
      def updated_lockfile_content
        @updated_lockfile_content ||= T.let(
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            options: options
          ).updated_lockfile_content,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def top_level_gemspecs
        dependency_files
          .select { |file| file.name.end_with?(".gemspec") }
      end

      sig { returns(String) }
      def bundler_version
        @bundler_version ||= T.let(
          Helpers.bundler_version(lockfile),
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("bundler", Dependabot::Bundler::FileUpdater)
