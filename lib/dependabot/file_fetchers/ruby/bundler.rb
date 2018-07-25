# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/errors"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler < Dependabot::FileFetchers::Base
        require "dependabot/file_fetchers/ruby/bundler/path_gemspec_finder"
        require "dependabot/file_fetchers/ruby/bundler/child_gemfile_finder"
        require "dependabot/file_fetchers/ruby/bundler/require_relative_finder"

        def self.required_files_in?(filenames)
          if filenames.include?("Gemfile.lock") &&
             !filenames.include?("Gemfile")
            return false
          end

          if filenames.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
            return true
          end

          filenames.include?("Gemfile")
        end

        def self.required_files_message
          "Repo must contain either a Gemfile or a gemspec. " \
          "A Gemfile.lock may only be present if a Gemfile is."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << gemfile if gemfile
          fetched_files << lockfile if lockfile
          fetched_files += gemspecs
          fetched_files << ruby_version_file if ruby_version_file
          fetched_files += child_gemfiles
          fetched_files += path_gemspecs
          fetched_files += require_relative_files(fetched_files)

          unless self.class.required_files_in?(fetched_files.map(&:name))
            raise "Invalid set of files: #{fetched_files.map(&:name)}"
          end

          fetched_files.uniq
        end

        def gemfile
          @gemfile ||=
            if gemspecs.any?
              fetch_file_if_present("Gemfile")
            else
              # This will raise if there is no Gemfile, which is what we want
              # (since there is no gemspec)
              fetch_file_from_host("Gemfile")
            end
        end

        def lockfile
          @lockfile ||= fetch_file_if_present("Gemfile.lock")
        end

        def gemspecs
          gemspecs = repo_contents.select { |f| f.name.end_with?(".gemspec") }
          @gemspecs ||= gemspecs.map { |gs| fetch_file_from_host(gs.name) }
        rescue Octokit::NotFound
          []
        end

        def ruby_version_file
          return unless gemfile
          return unless gemfile.content.include?(".ruby-version")
          fetch_file_if_present(".ruby-version")
        end

        def path_gemspecs
          gemspec_files = []
          unfetchable_gems = []

          gemspec_paths = fetch_gemspec_paths

          gemspec_paths.each do |path|
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

          gemspec_files
        end

        def require_relative_files(files)
          ruby_files =
            files.select { |f| f.name.end_with?(".rb", "Gemfile", ".gemspec") }

          paths = ruby_files.flat_map do |file|
            RequireRelativeFinder.new(file: file).require_relative_paths
          end

          @require_relative_files ||=
            paths.map { |fp| fetch_file_from_host(fp) }
        end

        def fetch_gemspecs_from_directory(dir_path)
          repo_contents(dir: dir_path).
            select { |f| f.name.end_with?(".gemspec") }.
            map { |f| File.join(dir_path, f.name) }.
            map { |fp| fetch_file_from_host(fp) }
        end

        def fetch_gemspec_paths
          if lockfile
            parsed_lockfile = ::Bundler::LockfileParser.new(lockfile.content)
            parsed_lockfile.specs.
              select { |s| s.source.instance_of?(::Bundler::Source::Path) }.
              map { |s| s.source.path }
          else
            gemfiles = ([gemfile] + child_gemfiles).compact
            gemfiles.flat_map do |file|
              PathGemspecFinder.new(gemfile: file).path_gemspec_paths
            end
          end
        rescue ::Bundler::LockfileError
          raise Dependabot::DependencyFileNotParseable, lockfile.path
        end

        def child_gemfiles
          return [] unless gemfile
          @child_gemfiles ||=
            fetch_child_gemfiles(file: gemfile, previously_fetched_files: [])
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
end
