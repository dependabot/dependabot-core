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
                  command: NativeHelpers.helper_path,
                  env: { "GO111MODULE" => "on" },
                  function: "updateDependencyFile",
                  args: { dependencies: deps }
                )
              end
            end
        end

        def updated_go_sum_content
          return nil unless go_sum

          # This needs to be run separately so we don't nest subprocess calls
          prepared_go_mod_content

          @updated_go_sum_content ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                # Create a fake empty module for each local module so that
                # `go get -d` works, even if some modules have been `replace`d
                # with a local module that we don't have access to.
                local_replacements.each do |_, stub_path|
                  Dir.mkdir(stub_path) unless Dir.exist?(stub_path)
                  FileUtils.touch(File.join(stub_path, "go.mod"))
                end

                File.write("go.mod", prepared_go_mod_content)
                File.write("go.sum", go_sum.content)
                File.write("main.go", dummy_main_go)

                env = { "GO111MODULE" => "on" }
                _, stderr, status = Open3.capture3(env, "go get -d")
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
          /verifying .*: checksum mismatch/.freeze,
          /build .*: cannot find module providing package/.freeze
        ].freeze
        MODULE_PATH_MISMATCH_REGEXES = [
          /go: ([^@\s]+)(?:@[^\s]+)?: .* has non-.* module path "(.*)" at/,
          /go: ([^@\s]+)(?:@[^\s]+)?: .* unexpected module path "(.*)"/
        ].freeze

        def local_replacements
          @local_replacements ||=
            SharedHelpers.in_a_temporary_directory do |path|
              File.write("go.mod", go_mod.content)

              # Parse the go.mod to get a JSON representation of the replace
              # directives
              command = "go mod edit -json"
              env = { "GO111MODULE" => "on" }
              stdout, stderr, status = Open3.capture3(env, command)
              handle_parser_error(path, stderr) unless status.success?

              # Find all the local replacements, and return them with a stub
              # path we can use in their place. Using generated paths is safer
              # as it means we don't need to worry about references to parent
              # directories, etc.
              (JSON.parse(stdout)["Replace"] || []).
                map { |r| r["New"]["Path"] }.
                compact.
                select { |p| p.start_with?(".") || p.start_with?("/") }.
                map { |p| [p, "./" + Digest::SHA2.hexdigest(p)] }
            end
        end

        def prepared_go_mod_content
          content = updated_go_mod_content
          local_replacements.reduce(content) do |body, (path, stub_path)|
            body.sub(path, stub_path)
          end
        end

        def handle_subprocess_error(path, stderr)
          error_regex = RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          if error_regex
            lines = stderr.lines.drop_while { |l| error_regex !~ l }
            raise Dependabot::DependencyFileNotResolvable.new, lines.join
          end

          path_regex = MODULE_PATH_MISMATCH_REGEXES.find { |r| stderr =~ r }
          if path_regex
            match = path_regex.match(stderr)
            raise Dependabot::GoModulePathMismatch.
              new(go_mod.path, match[1], match[2])
          end

          msg = stderr.gsub(path.to_s, "").lines.last(10).join.strip
          raise Dependabot::DependencyFileNotParseable.new(go_mod.path, msg)
        end

        def dummy_main_go
          # If we use `main` as the package name, running `go get -d` seems to
          # invoke the build systems, which can cause problems. For instance,
          # if the go.mod includes a module that doesn't have a top-level
          # package, we have no way of working out the import path, so the
          # build step fails.
          #
          # In due course, if we end up fetching the full repo, it might be
          # good to switch back to `main` so we can surface more errors.
          lines = ["package dummypkg", "import ("]
          dependencies.each do |dep|
            lines << "_ \"#{dep.name}\""
          end
          lines << ")"
          lines.join("\n")
        end

        attr_reader :dependencies, :go_mod, :go_sum, :credentials
      end
    end
  end
end
