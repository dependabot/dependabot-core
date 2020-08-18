# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Bundler
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/gemfile_updater"
      require_relative "file_updater/gemspec_updater"
      require_relative "file_updater/lockfile_updater"

      def self.updated_files_regex
        [
          /^Gemfile$/,
          /^Gemfile\.lock$/,
          /^gems\.rb$/,
          /^gems\.locked$/,
          /^*\.gemspec$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if gemfile && file_changed?(gemfile)
          updated_files <<
            updated_file(
              file: gemfile,
              content: updated_gemfile_content(gemfile)
            )
        end

        if lockfile && dependencies.any?(&:appears_in_lockfile?)
          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)
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

        base_dir = updated_files.first.directory
        if repo_path
          Dir.chdir(repo_path) do
            app_cache_dir = SharedHelpers.in_a_forked_process do
              # Set the path for path gemspec correctly
              ::Bundler.instance_variable_set(:@root, repo_path)
              ::Bundler.app_cache
            end
            app_cache_dir = app_cache_dir&.sub("#{repo_path}/", "")

            status = `git status --porcelain=v1`
            paths = status.split("\n").map { |l| l.split(" ") }
            paths.each do |type, path|
              if app_cache_dir && !path.start_with?(app_cache_dir.to_s)
                next
              end
              next if updated_files.any? { |f| f.name == path }

              content = type == "D" ? nil : File.read(path)
              updated_file = Dependabot::DependencyFile.new(
                name: path,
                content: content,
                directory: base_dir
              )
              updated_files << updated_file
            end
          end
        end
        updated_files
      end

      private

      def check_required_files
        file_names = dependency_files.map(&:name)

        if lockfile && !gemfile
          raise "A Gemfile must be provided if a lockfile is!"
        end

        return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
      end

      def check_updated_files(updated_files)
        return if updated_files.reject { |f| dependency_files.include?(f) }.any?

        raise "No files have changed!"
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile") ||
                     get_original_file("gems.rb")
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock") ||
                      get_original_file("gems.locked")
      end

      def evaled_gemfiles
        @evaled_gemfiles ||=
          dependency_files.
          reject { |f| f.name.end_with?(".gemspec") }.
          reject { |f| f.name.end_with?(".specification") }.
          reject { |f| f.name.end_with?(".lock") }.
          reject { |f| f.name.end_with?(".ruby-version") }.
          reject { |f| f.name == "Gemfile" }.
          reject { |f| f.name == "gems.rb" }.
          reject { |f| f.name == "gems.locked" }
      end

      def updated_gemfile_content(file)
        GemfileUpdater.new(
          dependencies: dependencies,
          gemfile: file
        ).updated_gemfile_content
      end

      def updated_gemspec_content(gemspec)
        GemspecUpdater.new(
          dependencies: dependencies,
          gemspec: gemspec
        ).updated_gemspec_content
      end

      def updated_lockfile_content
        @updated_lockfile_content ||=
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_path: repo_path,
            credentials: credentials
          ).updated_lockfile_content
      end

      def top_level_gemspecs
        dependency_files.
          select { |file| file.name.end_with?(".gemspec") }.
          reject(&:support_file?)
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("bundler", Dependabot::Bundler::FileUpdater)
