# frozen_string_literal: true
require "gems"
require "bump/update_checkers/base"
require "bump/shared_helpers"
require "bump/errors"

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
        # If this dependency doesn't have a source specified we use the default
        # one, which is Rubygems.
        return Gems.info(dependency.name)["version"] if gem_source.nil?

        # Otherwise, if the source is anything other than a Rubygems server
        # we just return `nil` and ignore the gem. This happens in the case of
        # a `git` or `path` source.
        return unless gem_source.is_a?(Bundler::Source::Rubygems)

        # Finally, when the source is a Rubygems server we piggyback off Bundler
        # to get the latest version.
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

      def gem_source
        @gem_source ||=
          SharedHelpers.in_a_temporary_directory do |dir|
            write_temporary_dependency_files_to(dir)

            SharedHelpers.in_a_forked_process do
              definition = Bundler::Definition.build(
                File.join(dir, "Gemfile"),
                File.join(dir, "Gemfile.lock"),
                nil
              )

              definition.dependencies.
                find { |dep| dep.name == dependency.name }.
                source
            end
          end
      rescue Bump::SharedHelpers::ChildProcessFailed => err
        raise unless err.error_class == "Bundler::Dsl::DSLError"

        msg = err.error_class + " with message: " + err.error_message
        raise Bump::DependencyFileNotEvaluatable, msg
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
