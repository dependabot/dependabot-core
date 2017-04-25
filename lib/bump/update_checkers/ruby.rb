# frozen_string_literal: true
require "gems"
require "bump/update_checkers/base"
require "bump/shared_helpers"

module Bump
  module UpdateCheckers
    class Ruby < Base
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      # Parse the Gemfile.lock to get the gem version. Better than just relying
      # on the dependency's specified version, which may have had a ~> matcher.
      def dependency_version
        parsed_lockfile = Bundler::LockfileParser.new(gemfile_lock.content)

        if dependency.name == "bundler"
          return Gem::Version.new(Bundler::VERSION)
        end

        # The safe navigation operator is necessary because not all files in
        # the Gemfile will appear in the Gemfile.lock. For instance, if a gem
        # specifies `platform: [:windows]`, and the Gemfile.lock is generated
        # on a Linux machine, the gem will be not appear in the lockfile.
        parsed_lockfile.specs.
          find { |spec| spec.name == dependency.name }&.
          version
      end

      private

      def fetch_latest_version
        # If this dependency doesn't have a source specified we can just use
        # Rubygems to get the latest version.
        return Gems.info(dependency.name)["version"] if gem_remotes.none?

        # Otherwise, we need to look at the versions in each of the specified
        # sources. To start with, get an array of Bundler::Dependency::Fetchers
        # for the remotes we need to look for this dependency at.
        gem_source = Bundler::Source::Rubygems.new("remotes" => gem_remotes)
        gem_fetchers =
          gem_source.fetchers.flat_map(&:fetchers).
          select { |f| f.is_a?(Bundler::Fetcher::Dependency) }

        # Fetch the versions of this dependency available from each remote.
        versions =
          gem_fetchers.
          flat_map { |f| f.unmarshalled_dep_gems([dependency.name]) }.
          map { |details| Gem::Version.new(details.fetch(:number)) }

        # Return the latest version that isn't a pre-release
        versions.reject(&:prerelease?).sort.last.version
      end

      def gem_remotes
        SharedHelpers.in_a_temporary_directory do |dir|
          write_temporary_dependency_files_to(dir)

          SharedHelpers.in_a_forked_process do
            definition = Bundler::Definition.build(
              File.join(dir, "Gemfile"),
              File.join(dir, "Gemfile.lock"),
              nil
            )

            remotes =
              definition.dependencies.
              find { |dep| dep.name == dependency.name }.
              source&.options&.fetch("remotes")

            remotes || []
          end
        end
      end

      def gemfile_lock
        lockfile = dependency_files.find { |f| f.name == "Gemfile.lock" }
        raise "No Gemfile.lock!" unless lockfile
        lockfile
      end

      def gemfile
        gemfile = dependency_files.find { |f| f.name == "Gemfile" }
        raise "No Gemfile!" unless gemfile
        gemfile
      end

      def language
        "ruby"
      end

      def write_temporary_dependency_files_to(dir)
        File.write(
          File.join(dir, "Gemfile"),
          gemfile.content
        )
        File.write(
          File.join(dir, "Gemfile.lock"),
          gemfile_lock.content
        )
      end
    end
  end
end
