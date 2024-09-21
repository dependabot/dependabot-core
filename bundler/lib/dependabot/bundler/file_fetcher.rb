# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/cached_lockfile_parser"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      require "dependabot/bundler/file_fetcher/gemspec_finder"
      require "dependabot/bundler/file_fetcher/path_gemspec_finder"
      require "dependabot/bundler/file_fetcher/child_gemfile_finder"
      require "dependabot/bundler/file_fetcher/included_path_finder"

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }

        filenames.include?("Gemfile") || filenames.include?("gems.rb")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain either a Gemfile, a gemspec, or a gems.rb."
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
      def ecosystem_versions
        {
          package_managers: {
            "bundler" => Helpers.detected_bundler_version(lockfile)
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])
        fetched_files << T.must(gemfile) if gemfile
        fetched_files << T.must(lockfile) if gemfile && lockfile
        fetched_files += child_gemfiles
        fetched_files += gemspecs
        fetched_files << T.must(ruby_version_file) if ruby_version_file
        fetched_files << T.must(tool_versions_file) if tool_versions_file
        fetched_files += path_gemspecs
        fetched_files += find_included_files(fetched_files)

        uniq_files(fetched_files)
      end

      private

      sig { params(fetched_files: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files
                      .reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      sig { returns(T.nilable(DependencyFile)) }
      def gemfile
        return @gemfile if defined?(@gemfile)

        @gemfile = T.let(fetch_file_if_present("gems.rb") || fetch_file_if_present("Gemfile"),
                         T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lockfile
        return @lockfile if defined?(@lockfile)

        @lockfile = T.let(fetch_file_if_present("gems.locked") || fetch_file_if_present("Gemfile.lock"),
                          T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def gemspecs
        return T.must(@gemspecs) if defined?(@gemspecs)

        gemspecs_paths =
          gemspec_directories
          .flat_map do |d|
            repo_contents(dir: d)
              .select { |f| f.name.end_with?(".gemspec") }
              .map { |f| File.join(d, f.name) }
          end

        @gemspecs ||= T.let(
          gemspecs_paths.map do |n|
            fetch_file_from_host(n)
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      rescue Octokit::NotFound
        []
      end

      sig { returns(T::Array[String]) }
      def gemspec_directories
        gemfiles = ([gemfile] + child_gemfiles).compact
        directories =
          gemfiles.flat_map do |file|
            GemspecFinder.new(gemfile: file).gemspec_directories
          end.uniq

        directories.empty? ? ["."] : directories
      end

      sig { returns(T.nilable(DependencyFile)) }
      def ruby_version_file
        return unless gemfile

        @ruby_version_file ||= T.let(fetch_support_file(".ruby-version"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def tool_versions_file
        return unless gemfile

        @tool_versions_file ||= T.let(fetch_support_file(".tool-versions"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def path_gemspecs
        gemspec_files = T.let([], T::Array[Dependabot::DependencyFile])
        unfetchable_gems = []

        path_gemspec_paths.each do |path|
          # Get any gemspecs at the path itself
          gemspecs_at_path = fetch_gemspecs_from_directory(path)

          # Get any gemspecs nested one level deeper
          nested_directories =
            repo_contents(dir: path)
            .select { |f| f.type == "dir" }

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

        raise Dependabot::PathDependenciesNotReachable, unfetchable_gems if unfetchable_gems.any?

        gemspec_files
      end

      sig { returns(T::Array[Pathname]) }
      def path_gemspec_paths
        fetch_path_gemspec_paths.map { |path| Pathname.new(path) }
      end

      sig { params(files: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def find_included_files(files)
        ruby_files =
          files.select { |f| f.name.end_with?(".rb", "Gemfile", ".gemspec") }

        paths = ruby_files.flat_map do |file|
          IncludedPathFinder.new(file: file).find_included_paths
        end

        @find_included_files ||= T.let(
          paths.map { |path| fetch_file_from_host(path) }
               .tap { |req_files| req_files.each { |f| f.support_file = true } },
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(dir_path: T.any(String, Pathname)).returns(T::Array[DependencyFile]) }
      def fetch_gemspecs_from_directory(dir_path)
        repo_contents(dir: dir_path, fetch_submodules: true)
          .select { |f| f.name.end_with?(".gemspec", ".specification") }
          .map { |f| File.join(dir_path, f.name) }
          .map { |fp| fetch_file_from_host(fp, fetch_submodules: true) }
      end

      sig { returns(T::Array[String]) }
      def fetch_path_gemspec_paths
        if lockfile
          parsed_lockfile = CachedLockfileParser.parse(T.must(sanitized_lockfile_content))
          parsed_lockfile.specs
                         .select { |s| s.source.instance_of?(::Bundler::Source::Path) }
                         .map { |s| s.source.path }.uniq
        else
          gemfiles = ([gemfile] + child_gemfiles).compact
          gemfiles.flat_map do |file|
            PathGemspecFinder.new(gemfile: file).path_gemspec_paths
          end.uniq
        end
      rescue ::Bundler::LockfileError
        raise Dependabot::DependencyFileNotParseable, T.must(lockfile).path
      rescue ::Bundler::Plugin::UnknownSourceError
        # Quietly ignore plugin errors - we'll raise a better error during
        # parsing
        []
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_gemfiles
        return [] unless gemfile

        @child_gemfiles ||= T.let(
          fetch_child_gemfiles(file: T.must(gemfile), previously_fetched_files: []),
          T.nilable(T::Array[DependencyFile])
        )
      end

      # TODO: Stop sanitizing the lockfile once we have bundler 2 installed

      sig { returns T.nilable(String) }
      def sanitized_lockfile_content
        regex = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
        lockfile&.content&.gsub(regex, "")
      end

      sig do
        params(file: DependencyFile,
               previously_fetched_files: T::Array[DependencyFile]).returns(T::Array[DependencyFile])
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

Dependabot::FileFetchers.register("bundler", Dependabot::Bundler::FileFetcher)
