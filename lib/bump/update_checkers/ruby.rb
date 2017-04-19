# frozen_string_literal: true
require "gems"
require "bump/update_checkers/base"

module Bump
  module UpdateCheckers
    class Ruby < Base
      def latest_version
        @latest_version ||= Gems.info(dependency.name)["version"]
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
        parsed_lockfile.
          specs.
          find { |spec| spec.name == dependency.name }&.
          version
      end

      private

      def gemfile_lock
        lockfile = dependency_files.find { |f| f.name == "Gemfile.lock" }
        raise "No Gemfile.lock!" unless lockfile
        lockfile
      end

      def language
        "ruby"
      end
    end
  end
end
