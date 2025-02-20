# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/go_modules/file_updater"
require "dependabot/go_modules/replace_stubber"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    class FileUpdater
      class GoModUpdater
        extend T::Sig

        RESOLVABILITY_ERROR_REGEXES = T.let([
          # The checksum in go.sum does not match the downloaded content
          /verifying .*: checksum mismatch/,
          /go(?: get)?: .*: go.mod has post-v\d+ module path/,
          # The Go tool is suggesting the user should run go mod tidy
          /go mod tidy/,
          # Something wrong in the chain of go.mod/go.sum files
          # These are often fixable with go mod tidy too.
          /no required module provides package/,
          /missing go\.sum entry for module providing package/,
          /missing go\.sum entry for go\.mod file/m,
          /malformed module path/,
          /used for two different module paths/,
          # https://github.com/golang/go/issues/56494
          /can't find reason for requirement on/,
          # import path doesn't exist
          /package \S+ is not in GOROOT/
        ].freeze, T::Array[Regexp])

        REPO_RESOLVABILITY_ERROR_REGEXES = T.let([
          /fatal: The remote end hung up unexpectedly/,
          /repository '.+' not found/,
          %r{net/http: TLS handshake timeout},
          # (Private) module could not be fetched
          /go(?: get)?: .*: git (fetch|ls-remote) .*: exit status 128/m,
          # (Private) module could not be found
          /cannot find module providing package/,
          # Package in module was likely renamed or removed
          /module.*found.*but does not contain package/m,
          # Package pseudo-version does not match the version-control metadata
          # https://golang.google.cn/doc/go1.13#version-validation
          /go(?: get)?: .*: invalid pseudo-version/m,
          # Package does not exist, has been pulled or cannot be reached due to
          # auth problems with either git or the go proxy
          /go(?: get)?: .*: unknown revision/m,
          # Package pointing to a proxy that 404s
          /go(?: get)?: .*: unrecognized import path/m,
          # Package not being referenced correctly
          /go:.*imports.*package.+is not in std/m
        ].freeze, T::Array[Regexp])

        MODULE_PATH_MISMATCH_REGEXES = T.let([
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* has non-.* module path "(.*)" at/,
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* unexpected module path "(.*)"/,
          /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?:? .* declares its path as: ([\S]*)/m
        ].freeze, T::Array[Regexp])

        OUT_OF_DISK_REGEXES = T.let([
          %r{input/output error},
          /no space left on device/,
          /Out of diskspace/
        ].freeze, T::Array[Regexp])

        GO_LANG = "Go"

        AMBIGUOUS_ERROR_MESSAGE = /ambiguous import: found package (?<package>.*) in multiple modules/

        GO_VERSION_MISMATCH = /requires go (?<current_ver>.*) .*running go (?<req_ver>.*);/

        GO_MOD_VERSION = /^go 1\.\d+(\.\d+)?$/

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            directory: String,
            options: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path:,
                       directory:, options:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @directory = directory
          @tidy = T.let(options.fetch(:tidy, false), T::Boolean)
          @vendor = T.let(options.fetch(:vendor, false), T::Boolean)
          @goprivate = T.let(options.fetch(:goprivate), T.nilable(String))
        end

        sig { returns(T.nilable(String)) }
        def updated_go_mod_content
          updated_files[:go_mod]
        end

        sig { returns(T.nilable(String)) }
        def updated_go_sum_content
          updated_files[:go_sum]
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(String) }
        attr_reader :directory

        sig { returns(T::Hash[Symbol, String]) }
        def updated_files
          @updated_files ||= T.let(update_files, T.nilable(T::Hash[Symbol, String]))
        end

        sig { returns(T::Hash[Symbol, String]) }
        def update_files # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
          in_repo_path do
            # During grouped updates, the dependency_files are from a previous dependency
            # update, so we need to update them on disk after the git reset in in_repo_path.
            dependency_files.each do |file|
              path = Pathname.new(file.name).expand_path
              FileUtils.mkdir_p(path.dirname)
              File.write(path, file.content)
            end

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
              go_mod_lines = T.let(updated_go_mod.lines, T::Array[T.nilable(String)])
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

        sig { void }
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

        sig { void }
        def run_go_vendor
          return unless vendor?

          command = "go mod vendor"
          _, stderr, status = Open3.capture3(environment, command)
          handle_subprocess_error(stderr) unless status.success?
        end

        sig { params(dependencies: T.untyped).void }
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
          FileUtils.rm_f(T.must(tmp_go_file))
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_manifest
          command = "go mod edit -json"
          stdout, stderr, status = Open3.capture3(environment, command)
          handle_subprocess_error(stderr) unless status.success?

          JSON.parse(stdout) || {}
        end

        sig do
          type_parameters(:T)
            .params(block: T.proc.returns(T.type_parameter(:T)))
            .returns(T.type_parameter(:T))
        end
        def in_repo_path(&block)
          SharedHelpers.in_a_temporary_repo_directory(directory, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials, &block)
          end
        end

        sig { params(stub_paths: T::Array[String]).void }
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
        sig { params(manifest: T::Hash[String, T.untyped]).returns(T::Hash[String, String]) }
        def replace_directive_substitutions(manifest)
          @replace_directive_substitutions ||=
            T.let(Dependabot::GoModules::ReplaceStubber.new(repo_contents_path)
                                                 .stub_paths(manifest, directory), T.nilable(T::Hash[String, String]))
        end

        sig { params(substitutions: T::Hash[String, String]).void }
        def substitute_all(substitutions)
          body = substitutions.reduce(File.read("go.mod")) do |text, (a, b)|
            text.sub(a, b)
          end

          write_go_mod(body)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(stderr: String).returns(T.noreturn) }
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
          ResolvabilityErrors.handle(stderr, goprivate: @goprivate) if repo_error_regex

          path_regex = MODULE_PATH_MISMATCH_REGEXES.find { |r| stderr =~ r }
          if path_regex
            match = T.must(path_regex.match(stderr))
            raise Dependabot::GoModulePathMismatch
              .new(go_mod_path, T.must(match[1]), T.must(match[2]))
          end

          out_of_disk_regex = OUT_OF_DISK_REGEXES.find { |r| stderr =~ r }
          if out_of_disk_regex
            error_message = filter_error_message(message: stderr, regex: out_of_disk_regex)
            raise Dependabot::OutOfDisk.new, error_message
          end

          if (matches = stderr.match(AMBIGUOUS_ERROR_MESSAGE))
            raise Dependabot::DependencyFileNotResolvable, matches[:package]
          end

          if (matches = stderr.match(GO_VERSION_MISMATCH))
            raise Dependabot::ToolVersionNotSupported.new(GO_LANG, T.must(matches[:current_ver]),
                                                          T.must(matches[:req_ver]))
          end

          # We don't know what happened so we raise a generic error
          msg = stderr.lines.last(10).join.strip
          raise Dependabot::DependabotError, msg
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(message: String, regex: Regexp).returns(String) }
        def filter_error_message(message:, regex:)
          lines = message.lines.select { |l| regex =~ l }
          return lines.join if lines.any?

          # In case the regex is multi-line, match the whole string
          message.match(regex).to_s
        end

        sig { returns(String) }
        def go_mod_path
          return "go.mod" if directory == "/"

          File.join(directory, "go.mod")
        end

        sig { params(body: Object).void }
        def write_go_mod(body)
          File.write("go.mod", body)
        end

        sig { returns(T::Boolean) }
        def tidy?
          !!@tidy
        end

        sig { returns(T::Boolean) }
        def vendor?
          !!@vendor
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def environment
          { "GOPRIVATE" => @goprivate }
        end
      end
    end
  end
end
