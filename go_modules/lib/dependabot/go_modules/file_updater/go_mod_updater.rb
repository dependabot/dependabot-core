# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
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

                command = "GO111MODULE=on go get -d"
                _, stderr, status = Open3.capture3(command)
                unless status.success?
                  handle_subprocess_error(go_sum.path, stderr)
                end

                File.read("go.sum")
              end
            end
        end

        private

        RESOLVABILITY_ERROR_REGEXES = [
          /go: .*: git fetch .*: exit status 128/.freeze,
          /go: verifying .*: checksum mismatch/.freeze,
          /build .*: cannot find module for path/.freeze
        ].freeze
        MODULE_PATH_MISMATCH_REGEX =
          /go: ([^@]+)(?:@.*)?: .* has non-.* module path "(.*)" at/.freeze

        def handle_subprocess_error(path, stderr)
          error_regex = RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          if error_regex
            lines = stderr.lines.drop_while { |l| error_regex !~ l }
            raise Dependabot::DependencyFileNotResolvable.new, lines.join
          end

          match = MODULE_PATH_MISMATCH_REGEX.match(stderr)
          if match
            raise Dependabot::GoModulePathMismatch.
              new(go_mod.path, match[1], match[2])
          end

          msg = stderr.gsub(path.to_s, "").lines.last(10).join.strip
          raise Dependabot::DependencyFileNotParseable.new(go_mod.path, msg)
        end

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
