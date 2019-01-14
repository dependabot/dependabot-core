# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/go_modules/file_updater"
require "dependabot/go_modules/native_helpers"

module Dependabot
  module GoModules
    class FileUpdater
      class GoModUpdater
        def initialize(dependencies:, go_mod:, go_sum:, credentials:)
          @dependencies = dependencies
          @go_mod = go_mod
          @go_sum = go_sum
          @credentials = credentials
        end

        def updated_go_mod_content
          @updated_go_mod_content ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                File.write("go.mod", go_mod.content)

                deps = dependencies.map do |dep|
                  {
                    name: dep.name,
                    version: "v" + dep.version.sub(/^v/i, ""),
                    indirect: dep.requirements.empty?
                  }
                end

                SharedHelpers.run_helper_subprocess(
                  command: "GO111MODULE=on #{NativeHelpers.helper_path}",
                  function: "updateDependencyFile",
                  args: { dependencies: deps }
                )
              end
            end
        end

        def updated_go_sum_content
          return nil unless go_sum

          # This needs to be run separately so we don't nest subprocess calls
          updated_go_mod_content

          @updated_go_sum_content ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                File.write("go.mod", updated_go_mod_content)
                File.write("go.sum", go_sum.content)
                File.write("main.go", dummy_main_go)

                `GO111MODULE=on go get -d`
                unless $CHILD_STATUS.success?
                  raise Dependabot::DependencyFileNotParseable, go_sum.path
                end

                File.read("go.sum")
              end
            end
        end

        private

        def dummy_main_go
          lines = ["package main", "import ("]
          dependencies.each do |dep|
            lines << "_ \"#{dep.name}\""
          end
          lines << ")"
          lines << "func main() {}"
          lines.join("\n")
        end

        attr_reader :dependencies, :go_mod, :go_sum, :credentials
      end
    end
  end
end
