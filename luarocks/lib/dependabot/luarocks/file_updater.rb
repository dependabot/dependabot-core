# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module LuaRocks
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/rockspec_updater"

      def self.updated_files_regex
        [
          /rockspec/,
        ]
      end

      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_rockspec_content(file)
            )
        end

        raise "No files have changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        raise "No Rockspec!" unless dependency_files.any?
      end

      def updated_rockspec_content(file)
        RockspecUpdater.new(
          dependencies: dependencies,
          rockspec_file: file
        ).updated_content
      end
    end
  end
end

Dependabot::FileUpdaters.register("luarocks", Dependabot::LuaRocks::FileUpdater)
