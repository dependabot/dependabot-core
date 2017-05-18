# frozen_string_literal: true
require "cocoapods"
require "bump/update_checkers/base"
require "bump/shared_helpers"
require "bump/errors"

module Bump
  module UpdateCheckers
    class Cocoa < Base
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      private

      def fetch_latest_version
        parsed_podfile = Pod::Podfile.from_ruby(nil, podfile.content)
        pod = parsed_podfile.dependencies.find { |d| d.name == dependency.name }

        return nil if pod.external_source

        source_manager = Pod::Config.instance.sources_manager
        analyzer = Pod::Installer::Analyzer.new(nil, parsed_podfile, nil)
        analyzer.config.silent = true
        analyzer.update_repositories

        sources =
          if pod.podspec_repo
            [source_manager.find_or_create_source_with_url(pod.podspec_repo)]
          else
            analyzer.sources
          end

        set = Pod::Specification::Set.new(pod.name, sources)
        Gem::Version.new(set.highest_version)
      end

      def lockfile
        lockfile = dependency_files.find { |f| f.name == "Podfile.lock" }
        raise "No Podfile.lock!" unless lockfile
        lockfile
      end

      def podfile
        podfile = dependency_files.find { |f| f.name == "Podfile" }
        raise "No Podfile!" unless podfile
        podfile
      end
    end
  end
end
