# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/go_modules/file_updater"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/replace_stubber"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    class FileUpdater
      class GoModUpdater
        RESOLVABILITY_ERROR_REGEXES = [
          # The checksum in go.sum does not match the downloaded content
          /verifying .*: checksum mismatch/,
          /go(?: get)?: .*: go.mod has post-v\d+ module path/,
          # The Go tool is suggesting the user should run go mod tidy
          /go mod tidy/,
          # Something wrong in the chain of go.mod/go.sum files
          # These are often fixable with go mod tidy too.
          /no required module provides package/,
          /missing go\.sum entry for module providing package/,
          /malformed module path/,
          /used for two different module paths/,
          # https://github.com/golang/go/issues/56494
          /can't find reason for requirement on/
        ].freeze

        REPO_RESOLVABILITY_ERROR_REGEXES = [
          /fatal: The remote end hung up unexpectedly/,
          /repository '.+' not found/,
          %r{net/http: TLS handshake timeout},
          # (Private) module could not be fetched
          /go(?: get)?: .*: git (fetch|ls-remote) .*: exit status 128/m,
          # (Private) module could not be found
          /cannot find module providing package/,
          # Package in module was likely renamed or removed
          /module .* found \(.*\), but does not contain package/m,
          # Package pseudo-version does not match the version-control metadata
          # https://golang.google.cn/doc/go1.13#version-validation
          /go(?: get)?: .*: invalid pseudo-version/m,
          # Package does not exist, has been pulled or cannot be reached due to
          # auth problems with either git or the go proxy
          /go(?: get)?: .*: unknown revision/m,
          # Package pointing to a proxy that 404s
          /go(?: get)?: .*: unrecognized import path/m
        ].freeze

        MODULE_PATH_MISMATCH_REGEXES = [
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* has non-.* module path "(.*)" at/,
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* unexpected module path "(.*)"/,
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?:? .* declares its path as: ([\S]*)/m
        ].freeze

        OUT_OF_DISK_REGEXES = [
          %r{input/output error},
          /no space left on device/
        ].freeze

        GO_MOD_VERSION = /^go 1\.[\d]+$/

        def initialize(dependencies:, credentials:, repo_contents_path:,
                       directory:, options:)
          @dependencies = dependencies
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @directory = directory
          @tidy = options.fetch(:tidy, false)
          @vendor = options.fetch(:vendor, false)
          @goprivate = options.fetch(:goprivate)
        end

        def updated_go_mod_content
          updated_files[:go_mod]
        end

        def updated_go_sum_content
          updated_files[:go_sum]
        end

        private

        attr_reader :dependencies, :credentials, :repo_contents_path,
                    :directory

        def updated_files
          @updated_files ||= update_files
        end

        def update_files # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
          in_repo_path do
            # Map paths in local replace directives to path hashes
            original_go_mod = File.read("go.mod")
            original_manifest = parse_manifest
            original_go_sum = File.read("go.sum") if File.exist?("go.sum")

            substitutions = replace_directive_substitutions(original_manifest)
            build_module_stubs(substitutions.values)

            # Replace full paths with path hashes in the go.mod
            substitute_all(substitutions)

            # Bump the deps we want to upgrade using `go get lib@version`
            run_go_get(dependencies)

            # Run `go get`'s internal validation checks against _each_ module in `go.mod`
            # by running `go get` w/o specifying any library. It finds problems like when a
            # module declares itself using a different name than specified in our `go.mod` etc.
            run_go_get

            # If we stubbed modules, don't run `go mod {tidy,vendor}` as
            # dependencies are incomplete
            if substitutions.empty?
              # go mod tidy should run before go mod vendor to ensure any
              # dependencies removed by go mod tidy are also removed from vendors.
              run_go_mod_tidy
              run_go_vendor
            else
              substitute_all(substitutions.invert)
            end

            updated_go_sum = original_go_sum ? File.read("go.sum") : nil
            updated_go_mod = File.read("go.mod")

            # running "go get" may inject the current go version, remove it
            original_go_version = original_go_mod.match(GO_MOD_VERSION)&.to_a&.first
            updated_go_version = updated_go_mod.match(GO_MOD_VERSION)&.to_a&.first
            if original_go_version != updated_go_version
              go_mod_lines = updated_go_mod.lines
              go_mod_lines.each_with_index do |line, i|
                next unless line&.match?(GO_MOD_VERSION)

                # replace with the original version
                go_mod_lines[i] = original_go_version
                # avoid a stranded newline if there was no version originally
                go_mod_lines[i + 1] = nil if original_go_version.nil?
              end

              updated_go_mod = go_mod_lines.compact.join
            end

            { go_mod: updated_go_mod, go_sum: updated_go_sum }
          end
        end

        def run_go_mod_tidy
          return unless tidy?

          command = "go mod tidy -e"

          # we explicitly don't raise an error for 'go mod tidy' and silently
          # continue with an info log here. `go mod tidy` shouldn't block
          # updating versions because there are some edge cases where it's OK to fail
          # (such as generated files not available yet to us).
          _, stderr, status = Open3.capture3(environment, command)
          Dependabot.logger.info "Failed to `go mod tidy`: #{stderr}" unless status.success?
        end

        def run_go_vendor
          return unless vendor?

          command = "go mod vendor"
          _, stderr, status = Open3.capture3(environment, command)
          handle_subprocess_error(stderr) unless status.success?
        end

        def run_go_get(dependencies = [])
          # `go get` will fail if there are no go files in the directory.
          # For example, if a `//go:build` tag excludes all files when run
          # on a particular architecture. However, dropping a go file with
          # a `package ...` line in it will always make `go get` succeed...
          # Even when the package name doesn't match the rest of the files
          # in the directory! I assume this is because it doesn't actually
          # compile anything when it runs.
          tmp_go_file = "#{SecureRandom.hex}.go"
          File.write(tmp_go_file, "package dummypkg\n")

          command = +"go get"
          # `go get` accepts multiple packages, each separated by a space
          dependencies.each do |dep|
            version = "v" + dep.version.sub(/^v/i, "")
            command << " #{dep.name}@#{version}"
          end
          command = SharedHelpers.escape_command(command)

          _, stderr, status = Open3.capture3(environment, command)
          handle_subprocess_error(stderr) unless status.success?
        ensure
          FileUtils.rm_f(tmp_go_file)
        end

        def parse_manifest
          command = "go mod edit -json"
          stdout, stderr, status = Open3.capture3(environment, command)
          handle_subprocess_error(stderr) unless status.success?

          JSON.parse(stdout) || {}
        end

        def in_repo_path(&block)
          SharedHelpers.in_a_temporary_repo_directory(directory, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials, &block)
          end
        end

        def build_module_stubs(stub_paths)
          # Create a fake empty module for each local module so that
          # `go get` works, even if some modules have been `replace`d
          # with a local module that we don't have access to.
          stub_paths.each do |stub_path|
            FileUtils.mkdir_p(stub_path)
            FileUtils.touch(File.join(stub_path, "go.mod"))
            FileUtils.touch(File.join(stub_path, "main.go"))
          end
        end

        # Given a go.mod file, find all `replace` directives pointing to a path
        # on the local filesystem, and return an array of pairs mapping the
        # original path to a hash of the path.
        #
        # This lets us substitute all parts of the go.mod that are dependent on
        # the layout of the filesystem with a structure we can reproduce (i.e.
        # no paths such as ../../../foo), run the Go tooling, then reverse the
        # process afterwards.
        def replace_directive_substitutions(manifest)
          @replace_directive_substitutions ||=
            Dependabot::GoModules::ReplaceStubber.new(repo_contents_path).
            stub_paths(manifest, directory)
        end

        def substitute_all(substitutions)
          body = substitutions.reduce(File.read("go.mod")) do |text, (a, b)|
            text.sub(a, b)
          end

          write_go_mod(body)
        end

        def handle_subprocess_error(stderr) # rubocop:disable Metrics/AbcSize
          stderr = stderr.gsub(Dir.getwd, "")

          # Package version doesn't match the module major version
          error_regex = RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          if error_regex
            error_message = filter_error_message(message: stderr, regex: error_regex)
            raise Dependabot::DependencyFileNotResolvable, error_message
          end

          if (matches = stderr.match(/Authentication failed for '(?<url>.+)'/))
            raise Dependabot::PrivateSourceAuthenticationFailure, matches[:url]
          end

          repo_error_regex = REPO_RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          if repo_error_regex
            error_message = filter_error_message(message: stderr, regex: repo_error_regex)
            ResolvabilityErrors.handle(error_message, credentials: credentials, goprivate: @goprivate)
          end

          path_regex = MODULE_PATH_MISMATCH_REGEXES.find { |r| stderr =~ r }
          if path_regex
            match = path_regex.match(stderr)
            raise Dependabot::GoModulePathMismatch.
              new(go_mod_path, match[1], match[2])
          end

          out_of_disk_regex = OUT_OF_DISK_REGEXES.find { |r| stderr =~ r }
          if out_of_disk_regex
            error_message = filter_error_message(message: stderr, regex: out_of_disk_regex)
            raise Dependabot::OutOfDisk.new, error_message
          end

          # We don't know what happened so we raise a generic error
          msg = stderr.lines.last(10).join.strip
          raise Dependabot::DependabotError, msg
        end

        def filter_error_message(message:, regex:)
          lines = message.lines.select { |l| regex =~ l }
          return lines.join if lines.any?

          # In case the regex is multi-line, match the whole string
          message.match(regex).to_s
        end

        def go_mod_path
          return "go.mod" if directory == "/"

          File.join(directory, "go.mod")
        end

        def write_go_mod(body)
          File.write("go.mod", body)
        end

        def tidy?
          !!@tidy
        end

        def vendor?
          !!@vendor
        end

        def environment
          { "GOPRIVATE" => @goprivate }
        end
      end
    end
  end
end
