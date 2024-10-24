# typed: true
# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module MavenOSV
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "utils/source_finder"

      def updated_dependency_files
        source = Utils::SourceFinder.from_repo(repo_contents_path:)
        return dependency_files unless source

        MavenOSV::FileFetcher.new(
          source:,
          credentials:,
          repo_contents_path:
        ).files
      end

      private

      def check_required_files
        raise "No pom.xml!" unless get_original_file("pom.xml")
      end
    end
  end
end

Dependabot::FileUpdaters.register("maven_osv", Dependabot::MavenOSV::FileUpdater)
