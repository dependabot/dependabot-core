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
                content: file_updater.updated_go_mod_content
              )

            if go_sum && go_sum.content != file_updater.updated_go_sum_content
              updated_files <<
                updated_file(
                  file: go_sum,
                  content: file_updater.updated_go_sum_content
                )
            end
          end

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        def check_required_files
          return if go_mod

          raise "No go.mod!"
        end

        def go_mod
          @go_mod ||= get_original_file("go.mod")
        end

        def go_sum
          @go_sum ||= get_original_file("go.sum")
        end

        def file_updater
          @file_updater ||=
            Modules::GoModUpdater.new(
              dependencies: dependencies,
              go_mod: go_mod,
              go_sum: go_sum,
              credentials: credentials
            )
        end
      end
    end
  end
end
