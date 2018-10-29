# frozen_string_literal: true

require "cocoapods"
require "gemnasium/parser"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Cocoa
      class CocoaPods < Dependabot::FileUpdaters::Base
        require_relative "cocoapods/podfile_updater"
        require_relative "cocoapods/lockfile_updater"

        POD_CALL =
          /^[ \t]*pod\(?[ \t]*#{Gemnasium::Parser::Patterns::QUOTED_GEM_NAME}
           (?:[ \t]*,[ \t]*#{Gemnasium::Parser::Patterns::REQUIREMENT_LIST})?/x

        LOCKFILE_ENDING = /(?<ending>\s*PODFILE CHECKSUM.*)/m

        def self.updated_files_regex
          [
            /^Podfile$/,
            /^Podfile\.lock$/
          ]
        end

        def updated_dependency_files
          [
            updated_file(file: podfile, content: updated_podfile_content),
            updated_file(file: lockfile, content: updated_lockfile_content)
          ]
        end

        private

        def check_required_files
          raise "No Podfile!" unless podfile
          raise "No Podfile.lock!" unless lockfile
        end

        def podfile
          @podfile ||= get_original_file("Podfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Podfile.lock")
        end

        def updated_lockfile_content
          @updated_lockfile_content ||= build_updated_lockfile

        end

        def evaluated_podfile
          @evaluated_podfile ||=
            Pod::Podfile.from_ruby(nil, updated_podfile_content)
        end

        def updated_podfile_content
          PodfileUpdater.new(
            dependencies: dependencies,
            podfile: podfile
          ).updated_podfile_content
        end

        def updated_lockfile_content
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile_content
        end
      end
    end
  end
end
