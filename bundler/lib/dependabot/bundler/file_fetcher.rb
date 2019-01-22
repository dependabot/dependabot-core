# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileFetcher < Dependabot::FileFetchers::Base
      require "dependabot/bundler/file_fetcher/gemspec_finder"
      require "dependabot/bundler/file_fetcher/path_gemspec_finder"
      require "dependabot/bundler/file_fetcher/child_gemfile_finder"
      require "dependabot/bundler/file_fetcher/require_relative_finder"

      def self.required_files_in?(filenames)
        if filenames.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return true
        end

        filenames.include?("Gemfile") || filenames.include?("gems.rb")
      end

      def self.required_files_message
        "Repo must contain either a Gemfile, a gemspec, or a gems.rb."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << gemfile if gemfile
        fetched_files << lockfile if gemfile && lockfile
        fetched_files += child_gemfiles
        fetched_files += gemspecs
        fetched_files << ruby_version_file if ruby_version_file
        fetched_files += path_gemspecs
        fetched_files += require_relative_files(fetched_files)

        fetched_files = uniq_files(fetched_files)

        check_required_files_present

        unless self.class.required_files_in?(fetched_files.map(&:name))
          raise "Invalid set of files: #{fetched_files.map(&:name)}"
        end

        fetched_files
      end

      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files.
                      reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      def check_required_files_present
        return if gemfile || gemspecs.any?

        path = Pathname.new(File.join(directory, "Gemfile")).
               cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def gemfile
        @gemfile ||= fetch_file_if_present("gems.rb") ||
                     fetch_file_if_present("Gemfile")
      end

      def lockfile
        @lockfile ||= fetch_file_if_present("gems.locked") ||
                      fetch_file_if_present("Gemfile.lock")
      end

      def gemspecs
        return @gemspecs if defined?(@gemspecs)

        gemspecs_paths =
          gemspec_directories.
          flat_map do |d|
            repo_contents(dir: d).
              select { |f| f.name.end_with?(".gemspec") }.
              map { |f| File.join(d, f.name) }
          end

        @gemspecs = gemspecs_paths.map { |n| fetch_file_from_host(n) }
      rescue Octokit::NotFound
        []
      end

      def gemspec_directories
        gemfiles = ([gemfile] + child_gemfiles).compact
        directories =
          gemfiles.flat_map do |file|
            GemspecFinder.new(gemfile: file).gemspec_directories
          end.uniq

        directories.empty? ? ["."] : directories
      end

      def ruby_version_file
        return unless gemfile
        return unless gemfile.content.include?(".ruby-version")

        @ruby_version_file ||=
          fetch_file_if_present(".ruby-version")&.
          tap { |f| f.support_file = true }
      end

      def path_gemspecs
        gemspec_files = []
        unfetchable_gems = []

        path_gemspec_paths.each do |path|
          # Get any gemspecs at the path itself
          gemspecs_at_path = fetch_gemspecs_from_directory(path)

          # Get any gemspecs nested one level deeper
          nested_directories =
            repo_contents(dir: path).
            select { |f| f.type == "dir" }

          nested_directories.each do |dir|
            dir_path = File.join(path, dir.name)
            gemspecs_at_path += fetch_gemspecs_from_directory(dir_path)
          end

          # Add the fetched gemspecs to the main array, and note an error if
          # none were found for this path
          gemspec_files += gemspecs_at_path
          unfetchable_gems << path.basename.to_s if gemspecs_at_path.empty?
        rescue Octokit::NotFound, Gitlab::Error::NotFound
          unfetchable_gems << path.basename.to_s
        end

        if unfetchable_gems.any?
          raise Dependabot::PathDependenciesNotReachable, unfetchable_gems
        end

        gemspec_files.tap { |ar| ar.each { |f| f.support_file = true } }
      end

      def path_gemspec_paths
        fetch_path_gemspec_paths.map { |path| Pathname.new(path) }
      end

      def require_relative_files(files)
        ruby_files =
          files.select { |f| f.name.end_with?(".rb", "Gemfile", ".gemspec") }

        paths = ruby_files.flat_map do |file|
          RequireRelativeFinder.new(file: file).require_relative_paths
        end

        @require_relative_files ||=
          paths.map { |path| fetch_file_from_host(path) }.
          tap { |req_files| req_files.each { |f| f.support_file = true } }
      end

      def fetch_gemspecs_from_directory(dir_path)
        repo_contents(dir: dir_path).
          select { |f| f.name.end_with?(".gemspec") }.
          map { |f| File.join(dir_path, f.name) }.
          map { |fp| fetch_file_from_host(fp) }
      end

      def fetch_path_gemspec_paths
        if lockfile
          parsed_lockfile = ::Bundler::LockfileParser.new(
            sanitized_lockfile_content
          )
          parsed_lockfile.specs.
            select { |s| s.source.instance_of?(::Bundler::Source::Path) }.
            map { |s| s.source.path }.uniq
        else
          gemfiles = ([gemfile] + child_gemfiles).compact
          gemfiles.flat_map do |file|
            PathGemspecFinder.new(gemfile: file).path_gemspec_paths
          end.uniq
        end
      rescue ::Bundler::LockfileError
        raise Dependabot::DependencyFileNotParseable, lockfile.path
      end

      def child_gemfiles
        return [] unless gemfile

        @child_gemfiles ||=
          fetch_child_gemfiles(file: gemfile, previously_fetched_files: [])
      end

      def sanitized_lockfile_content
        regex = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
        lockfile.content.gsub(regex, "")
      end

      def fetch_child_gemfiles(file:, previously_fetched_files:)
        paths = ChildGemfileFinder.new(gemfile: file).child_gemfile_paths

        paths.flat_map do |path|
          next if previously_fetched_files.map(&:name).include?(path)
          next if file.name == path

          fetched_file = fetch_file_from_host(path)
          grandchild_gemfiles = fetch_child_gemfiles(
            file: fetched_file,
            previously_fetched_files: previously_fetched_files + [file]
          )
          [fetched_file, *grandchild_gemfiles]
        end.compact
      end
    end
  end
end
