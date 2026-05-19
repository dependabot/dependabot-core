# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/go_modules/file_updater"
require "dependabot/go_modules/go_work_parser"
require "dependabot/go_modules/replace_stubber"
require "dependabot/go_modules/resolvability_errors"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class FileUpdater
      class GoModUpdater # rubocop:disable Metrics/ClassLength
        extend T::Sig

        RESOLVABILITY_ERROR_REGEXES = T.let(
          [
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
          ].freeze,
          T::Array[Regexp]
        )

        REPO_RESOLVABILITY_ERROR_REGEXES = T.let(
          [
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
            # Private repository cannot be fetched over a secure protocol
            Dependabot::GoModules::ResolvabilityErrors::INSECURE_PROTOCOL_REPOSITORY_REGEX,
            # Package not being referenced correctly
            /go:.*imports.*package.+is not in std/m,
            # Invalid version due to missing go.mod files at specified revision
            /go: .*: invalid version: missing .*go\.mod.* at revision/m
          ].freeze,
          T::Array[Regexp]
        )

        MODULE_PATH_MISMATCH_REGEXES = T.let(
          [
            /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* has non-.* module path "(.*)" at/,
            /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?: .* unexpected module path "(.*)"/,
            /go(?: get)?: ([^@\s]+)(?:@[^\s]+)?:? .* declares its path as: ([\S]*)/m
          ].freeze,
          T::Array[Regexp]
        )

        OUT_OF_DISK_REGEXES = T.let(
          [
            %r{input/output error},
            /no space left on device/,
            /Out of diskspace/
          ].freeze,
          T::Array[Regexp]
        )

        GO_MOD_PARSE_ERROR_REGEXES = T.let(
          [
            # go.mod file parsing errors
            /go: error loading go\.mod:/,
            /go\.mod:\d+: .*unknown.*/,
            /go\.mod:\d+: .*syntax error.*/,
            /go\.mod:\d+: .*invalid.*/
          ].freeze,
          T::Array[Regexp]
        )

        PATH_DEPENDENCY_ERROR_REGEXES = T.let(
          [
            /replaced by (?<path>[^)\s]+)\): reading .*go\.mod: open .*: no such file or directory/
          ].freeze,
          T::Array[Regexp]
        )

        GO_LANG = "Go"

        AMBIGUOUS_ERROR_MESSAGE = /ambiguous import: found package (?<package>.*) in multiple modules/

        GO_VERSION_MISMATCH = /requires go (?<current_ver>.*) .*running go (?<req_ver>.*);/

        GITHUB_403_REGEX =
          %r{https://github\.com/(?<repo>[^/'\s]+/[^/'\s]+)/?': The requested URL returned error: 403}

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
        def initialize(
          dependencies:,
          dependency_files:,
          credentials:,
          repo_contents_path:,
          directory:,
          options:
        )
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @directory = directory
          @tidy = T.let(options.fetch(:tidy, false), T::Boolean)
          @vendor = T.let(options.fetch(:vendor, false), T::Boolean)
        end

        sig { returns(T.nilable(String)) }
        def updated_go_mod_content
          updated_files[:go_mod]
        end

        sig { returns(T.nilable(String)) }
        def updated_go_sum_content
          updated_files[:go_sum]
        end

        sig { returns(T::Hash[String, String]) }
        def updated_workspace_module_files
          @updated_workspace_module_files ||= T.let(
            update_workspace_files,
            T.nilable(T::Hash[String, String])
          )
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
        def update_files
          in_repo_path do
            # During grouped updates, the dependency_files are from a previous dependency
            # update, so we need to update them on disk after the git reset in in_repo_path.
            dependency_files.each do |file|
              path = Pathname.new(file.name).expand_path
              FileUtils.mkdir_p(path.dirname)
              File.write(path, file.content)
            end

            # Map paths in local replace directives to path hashes
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

            updated_go_mod = File.read("go.mod")

            result = T.let({ go_mod: updated_go_mod }, T::Hash[Symbol, String])
            result[:go_sum] = reconcile_go_sum(original_go_sum, File.read("go.sum")) if original_go_sum

            result
          end
        end

        sig { returns(T::Hash[String, String]) }
        def update_workspace_files
          in_repo_path do
            dependency_files.each do |file|
              path = Pathname.new(file.name).expand_path
              FileUtils.mkdir_p(path.dirname)
              File.write(path, file.content)
            end

            # Run `go get dep@version` in each module directory so every go.mod
            # that requires the dependency gets the version bump, not just the first.
            # Follow with a bare `go get` validation pass per module, matching the
            # single-module update path's intent (see run_go_get comment).
            workspace_module_paths.each do |mod_dir|
              Dir.chdir(mod_dir) do
                run_go_get(dependencies)
                run_go_get
              end
            end

            run_go_work_sync
            run_workspace_tidy

            collect_workspace_file_contents
          end
        end

        sig { void }
        def run_go_work_sync
          command = "go work sync"
          _, stderr, status = Open3.capture3(command)
          return if status.success?

          handle_subprocess_error(stderr)
        end

        sig { void }
        def run_workspace_tidy
          return unless tidy?

          workspace_module_paths.each do |mod_path|
            Dir.chdir(mod_path) do
              command = "go mod tidy -e"
              _, stderr, status = Open3.capture3(command)
              if status.success?
                Dependabot.logger.info "`go mod tidy` succeeded in #{mod_path}"
              else
                Dependabot.logger.info "Failed to `go mod tidy` in #{mod_path}: #{stderr}"
              end
            end
          end
        end

        sig { returns(T::Array[String]) }
        def workspace_module_paths
          go_work_file = dependency_files.find { |f| f.name.end_with?("go.work") }
          return ["."] unless go_work_file

          fetched_mod_names = dependency_files.select { |f| f.name.end_with?("go.mod") }
                                              .to_set(&:name)

          GoWorkParser.use_paths(T.must(go_work_file.content))
                      .select { |p| valid_workspace_path?(p) && fetched_mod_names.include?(workspace_mod_name(p)) }
                      .map { |p| p == "." ? "." : "./#{p}" }
        end

        sig { params(path: String).returns(T::Boolean) }
        def valid_workspace_path?(path)
          return false if Pathname.new(path).absolute?

          !Pathname.new(path).cleanpath.to_s.start_with?("../")
        end

        sig { params(use_path: String).returns(String) }
        def workspace_mod_name(use_path)
          use_path == "." ? "go.mod" : "#{use_path}/go.mod"
        end

        sig { returns(T::Hash[String, String]) }
        def collect_workspace_file_contents
          results = T.let({}, T::Hash[String, String])

          workspace_module_paths.each do |mod_path|
            relative_base = mod_path.delete_prefix("./")

            mod_file = File.join(mod_path, "go.mod")
            if File.exist?(mod_file)
              key = relative_base.empty? || relative_base == "." ? "go.mod" : "#{relative_base}/go.mod"
              results[key] = File.read(mod_file)
            end

            sum_file = File.join(mod_path, "go.sum")
            next unless File.exist?(sum_file)

            key = relative_base.empty? || relative_base == "." ? "go.sum" : "#{relative_base}/go.sum"
            results[key] = File.read(sum_file)
          end

          results["go.work.sum"] = File.read("go.work.sum") if File.exist?("go.work.sum")

          results
        end

        sig { void }
        def run_go_mod_tidy
          return unless tidy?

          command = "go mod tidy -e"

          # we explicitly don't raise an error for 'go mod tidy' and silently
          # continue with an info log here. `go mod tidy` shouldn't block
          # updating versions because there are some edge cases where it's OK to fail
          # (such as generated files not available yet to us).
          _, stderr, status = Open3.capture3(command)
          if status.success?
            Dependabot.logger.info "`go mod tidy` succeeded"
          else
            Dependabot.logger.info "Failed to `go mod tidy`: #{stderr}"
          end
        end

        sig { void }
        def run_go_vendor
          return unless vendor?

          command = "go mod vendor"
          _, stderr, status = Open3.capture3(command)
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

          _, stderr, status = Open3.capture3(command)
          handle_subprocess_error(stderr) unless status.success?
        ensure
          FileUtils.rm_f(T.must(tmp_go_file))
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_manifest
          command = "go mod edit -json"
          stdout, stderr, status = Open3.capture3(command)
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

        sig { params(original_go_sum: String, updated_go_sum: String).returns(String) }
        def reconcile_go_sum(original_go_sum, updated_go_sum)
          original_lines = original_go_sum.lines(chomp: true).reject(&:empty?)
          updated_lines = updated_go_sum.lines(chomp: true).reject(&:empty?)
          updated_set = updated_lines.to_set
          updated_modules = extract_module_path_versions(updated_lines)

          restored_lines = find_restorable_go_mod_lines(original_lines, updated_set, updated_modules)
          return updated_go_sum if restored_lines.empty?

          (updated_lines + restored_lines).sort! { |a, b| go_sum_line_compare(a, b) }.join("\n") + "\n"
        end

        sig do
          params(
            original_lines: T::Array[String],
            updated_set: T::Set[String],
            updated_modules: T::Hash[String, T::Set[String]]
          ).returns(T::Array[String])
        end
        def find_restorable_go_mod_lines(original_lines, updated_set, updated_modules)
          original_zip_versions = build_original_zip_versions(original_lines)

          original_lines.filter_map do |line|
            next unless go_mod_checksum_line?(line)
            next if updated_set.include?(line)
            next unless restorable_line?(line, updated_modules, original_zip_versions)

            line
          end
        end

        sig do
          params(
            line: String,
            updated_modules: T::Hash[String, T::Set[String]],
            original_zip_versions: T::Hash[String, T::Set[String]]
          ).returns(T::Boolean)
        end
        def restorable_line?(line, updated_modules, original_zip_versions)
          module_path = go_sum_module_path(line)
          return false unless module_path
          return false if updated_dependency_names.include?(module_path)

          module_version = extract_module_version_from_go_mod_line(line)
          return false unless module_version

          version = T.must(module_version.split(/\s+/, 2).last)
          has_zip_in_original = original_zip_versions.fetch(module_path, nil)&.include?(version)

          if has_zip_in_original
            module_version_still_relevant?(module_path, module_version, updated_modules)
          else
            updated_modules.key?(module_path)
          end
        end

        # Builds a map of module_path → Set[versions] for entries that have a
        # zip hash (non /go.mod lines) in the original go.sum.
        sig { params(lines: T::Array[String]).returns(T::Hash[String, T::Set[String]]) }
        def build_original_zip_versions(lines)
          lines.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |line, map|
            next if go_mod_checksum_line?(line)

            parts = line.split(/\s+/, 3)
            next unless parts.length >= 2

            path = T.must(parts[0])
            version = T.must(parts[1])
            map[path].add(version)
          end
        end

        sig { params(line: String).returns(T::Boolean) }
        def go_mod_checksum_line?(line)
          line.include?("/go.mod h1:")
        end

        sig { params(line: String).returns(T.nilable(String)) }
        def go_sum_module_path(line)
          line.split(/\s+/, 2).first
        end

        # Extracts "module/path vX.Y.Z" from a /go.mod checksum line
        sig { params(line: String).returns(T.nilable(String)) }
        def extract_module_version_from_go_mod_line(line)
          match = line.match(%r{^(\S+)\s+(\S+)/go\.mod\s})
          return nil unless match

          "#{match[1]} #{match[2]}"
        end

        # Builds a map of module_path → Set[versions] from all lines in go.sum
        sig { params(lines: T::Array[String]).returns(T::Hash[String, T::Set[String]]) }
        def extract_module_path_versions(lines)
          lines.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |line, map|
            parts = line.split(/\s+/, 3)
            next unless parts.length >= 2

            path = T.must(parts[0])
            version = T.must(parts[1]).sub(%r{/go\.mod$}, "")
            map[path].add(version)
          end
        end

        # A module+version is still relevant if it still has an entry in the
        # updated go.sum (zip hash or another /go.mod line for the same version).
        # If the module path has no entry for this version, it was removed from
        # the graph (e.g., a transitive dep that was upgraded to a newer version).
        sig do
          params(
            module_path: String,
            module_version: String,
            updated_modules: T::Hash[String, T::Set[String]]
          ).returns(T::Boolean)
        end
        def module_version_still_relevant?(module_path, module_version, updated_modules)
          versions = updated_modules.fetch(module_path, nil)
          return false unless versions

          version = module_version.split(/\s+/, 2).last
          return false unless version

          versions.include?(version)
        end

        sig { returns(T::Set[String]) }
        def updated_dependency_names
          @updated_dependency_names ||= T.let(dependencies.to_set(&:name), T.nilable(T::Set[String]))
        end

        # Compares two go.sum lines using Go's module-aware sort order:
        # sort by module path, then semver version, then /go.mod suffix last.
        sig { params(line_a: String, line_b: String).returns(Integer) }
        def go_sum_line_compare(line_a, line_b)
          path_a, version_rest_a = line_a.split(/\s+/, 2)
          path_b, version_rest_b = line_b.split(/\s+/, 2)

          path_cmp = T.must((path_a || "") <=> (path_b || ""))
          return path_cmp unless path_cmp.zero?

          compare_go_versions(version_rest_a || "", version_rest_b || "")
        end

        # Compares version+suffix portions of go.sum lines using GoModules::Version.
        sig { params(ver_a: String, ver_b: String).returns(Integer) }
        def compare_go_versions(ver_a, ver_b)
          a_is_gomod = ver_a.include?("/go.mod")
          b_is_gomod = ver_b.include?("/go.mod")

          # Extract raw version token (e.g., "v0.6.0" from "v0.6.0/go.mod h1:...")
          raw_a = ver_a.split(%r{(/go\.mod)?\s}, 2).first || ""
          raw_b = ver_b.split(%r{(/go\.mod)?\s}, 2).first || ""

          ver_cmp = go_version_compare(raw_a, raw_b)
          return ver_cmp unless ver_cmp.zero?

          # Same version: zip hash line sorts before /go.mod line
          (a_is_gomod ? 1 : 0) <=> (b_is_gomod ? 1 : 0)
        end

        sig { params(ver_a: String, ver_b: String).returns(Integer) }
        def go_version_compare(ver_a, ver_b)
          T.must(Dependabot::GoModules::Version.new(ver_a) <=> Dependabot::GoModules::Version.new(ver_b))
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
            T.let(
              Dependabot::GoModules::ReplaceStubber.new(T.must(repo_contents_path))
                                                               .stub_paths(manifest, directory),
              T.nilable(T::Hash[String, String])
            )
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
        def handle_subprocess_error(stderr) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          stderr = stderr.gsub(Dir.getwd, "")

          raise_for_go_mod_parse_error(stderr)
          raise_for_path_dependency_error(stderr)

          # Package version doesn't match the module major version
          error_regex = RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          if error_regex
            error_message = filter_error_message(message: stderr, regex: error_regex)
            raise Dependabot::DependencyFileNotResolvable, error_message
          end

          if (matches = stderr.match(/Authentication failed for '(?<url>.+)'/))
            raise Dependabot::PrivateSourceAuthenticationFailure, matches[:url]
          end

          if github_credentials_configured? && (matches = stderr.match(GITHUB_403_REGEX))
            raise Dependabot::PrivateSourceAuthenticationFailure, "https://github.com/#{matches[:repo]}"
          end

          repo_error_regex = REPO_RESOLVABILITY_ERROR_REGEXES.find { |r| stderr =~ r }
          Dependabot::GoModules::ResolvabilityErrors.handle(stderr) if repo_error_regex

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
            raise Dependabot::ToolVersionNotSupported.new(
              GO_LANG,
              T.must(matches[:current_ver]),
              T.must(matches[:req_ver])
            )
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

        sig { params(message: String).returns(T.nilable(String)) }
        def extract_replacement_path(message)
          PATH_DEPENDENCY_ERROR_REGEXES.each do |regex|
            match = regex.match(message)
            return match[:path] if match
          end

          nil
        end

        sig { returns(T::Boolean) }
        def github_credentials_configured?
          credentials.any? do |credential|
            credential["type"] == "git_source" && credential["host"] == "github.com"
          end
        end

        sig { params(stderr: String).void }
        def raise_for_go_mod_parse_error(stderr)
          go_mod_parse_error_regex = GO_MOD_PARSE_ERROR_REGEXES.find { |r| stderr =~ r }
          return unless go_mod_parse_error_regex

          error_message = filter_error_message(message: stderr, regex: go_mod_parse_error_regex)
          raise Dependabot::DependencyFileNotParseable.new(go_mod_path, error_message)
        end

        sig { params(stderr: String).void }
        def raise_for_path_dependency_error(stderr)
          path_error_regex = PATH_DEPENDENCY_ERROR_REGEXES.find { |r| stderr =~ r }
          return unless path_error_regex

          dependency_path = extract_replacement_path(stderr)
          raise Dependabot::PathDependenciesNotReachable, [dependency_path] if dependency_path

          error_message = filter_error_message(message: stderr, regex: path_error_regex)
          raise Dependabot::DependencyFileNotResolvable, error_message
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
      end
    end
  end
end
