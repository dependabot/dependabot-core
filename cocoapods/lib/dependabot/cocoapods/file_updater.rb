# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module CocoaPods
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/podfile_updater"
      require_relative "file_updater/lockfile_updater"

      WORD = %r{[a-zA-Z0-9\-_./]+}.freeze
      POD_NAME = /(('|")(?<q_name>#{WORD})('|")|(?<name>#{WORD}))/.freeze

      POD_VERSION = /((\d+)\.(\d+)\.(\*|\d+))/.freeze
      MATCHER = /(?:=|!=|>|<|>=|<=|~>)/.freeze
      REQUIREMENT = /[ \t]*(?:#{MATCHER}[ \t]*)?#{POD_VERSION}[ \t]*/.freeze

      REQUIREMENT_LIST = /(?<qr1>["'])(?<req1>#{REQUIREMENT})
        \k<qr1>(?:[ \t]*,[ \t]*(?<qr2>["'])(?<req2>#{REQUIREMENT})
        \k<qr2>)?/.freeze
      REQUIREMENTS = /(?:#{REQUIREMENT_LIST}|
        \[[ \t]*#{REQUIREMENT_LIST}[ \t]*\])/.freeze

      POD_CALL = /^\s*pod\s*#{POD_NAME},\s*('|")#{REQUIREMENT}('|")/.freeze

      LOCKFILE_ENDING = /(?<ending>\s*PODFILE CHECKSUM.*)/m.freeze

      def self.updated_files_regex
        [
          /^Podfile$/,
          /^Podfile\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if podfile && file_changed?(podfile)
          updated_files <<
            updated_file(file: podfile, content: updated_podfile_content)
        end

        if lockfile && dependencies.any?(&:appears_in_lockfile?)
          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)
        end

        updated_files
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

      def updated_podfile_content
        PodfileUpdater.new(
          dependencies: dependencies,
          podfile: podfile
        ).updated_podfile_content
      end

      def updated_lockfile_content
        LockfileUpdater.new(
          dependencies: dependencies,
          updated_podfile_content: updated_podfile_content,
          lockfile: lockfile,
          credentials: credentials
        ).updated_lockfile_content
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("cocoapods", Dependabot::CocoaPods::FileUpdater)
