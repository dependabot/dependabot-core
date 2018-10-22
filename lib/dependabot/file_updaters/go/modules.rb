# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Go
      class Modules < Dependabot::FileUpdaters::Base
        require_relative "modules/go_mod_updater"

        def self.updated_files_regex
          [
            /^go\.mod$/,
            /^go\.sum$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if go_mod && file_changed?(go_mod)
            updated_files <<
              updated_file(
                file: go_mod,
                content: updated_go_mod_content
              )
          end

          # TODO: go.sum

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        def check_required_files
          return if get_original_file("go.mod")
          raise "No go.mod!"
        end

        def go_mod
          @go_mod ||= get_original_file("go.mod")
        end

        def updated_go_mod_content
          Modules::GoModUpdater.new(
            dependencies: dependencies,
            go_mod: go_mod,
            credentials: credentials
          ).updated_go_mod_content
        end
      end
    end
  end
end
