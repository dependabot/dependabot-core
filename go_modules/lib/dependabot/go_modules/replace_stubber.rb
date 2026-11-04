# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"
require "tmpdir"
require "dependabot/errors"
require "dependabot/go_modules/go_work_parser"
require "dependabot/go_modules/go_mod_manifest"

module Dependabot
  module GoModules
    # Workspace members must agree on each external replacement target.
    # Temporary edits share resolved targets and restore original bindings
    # before returning changes or propagating a tooling failure.
    class ReplaceStubber
      extend T::Sig

      ErrorHandler = T.type_alias { T.proc.params(stderr: String).returns(T.noreturn) }

      class ReplacementBinding < T::ImmutableStruct
        const :manifest, String
        const :kind, String
        const :old, GoModManifest::ModuleReference
        const :original, String
        const :stub, String
      end

      sig { params(repo_contents_path: String).void }
      def initialize(repo_contents_path)
        @repo_contents_path = T.let(Pathname.new(repo_contents_path).realpath, Pathname)
      end

      sig do
        params(manifest: GoModManifest, directory: T.nilable(String), stub_root: T.nilable(String))
          .returns(T::Hash[String, String])
      end
      def stub_paths(manifest, directory, stub_root: nil)
        paths = manifest.replacements.map { |replacement| replacement.new.path }
        paths.select { |path| stub_replace_path?(path, directory) }.to_h do |path|
          identity = Digest::SHA2.hexdigest(resolved_path(path, directory).to_s)
          [path, stub_root ? File.join(stub_root, identity) : "./#{identity}"]
        end
      end

      sig do
        type_parameters(:T)
          .params(on_error: ErrorHandler, _block: T.proc.params(stubbed: T::Boolean).returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def with_stubs(on_error:, &_block)
        Dir.mktmpdir("dependabot-replacements-") do |stub_root|
          bindings = replacement_bindings(stub_root, on_error: on_error)
          build_module_stubs(bindings.map(&:stub).uniq)
          begin
            edit_replacement_bindings(bindings, restore: false, on_error: on_error)
            yield(!bindings.empty?)
          ensure
            edit_replacement_bindings(bindings, restore: true, on_error: on_error)
          end
        end
      end

      private

      sig { params(path: String, directory: T.nilable(String)).returns(T::Boolean) }
      def stub_replace_path?(path, directory)
        return false unless absolute_path?(path) || relative_replacement_path?(path)

        resolved = resolved_path(path, directory)
        return true unless resolved.exist?

        resolved != @repo_contents_path && !resolved.to_s.start_with?("#{@repo_contents_path}/")
      end

      sig { params(path: String, directory: T.nilable(String)).returns(Pathname) }
      def resolved_path(path, directory)
        resolve_existing_ancestor(module_pathname(directory).join(path).cleanpath)
      end

      sig { params(path: Pathname).returns(Pathname) }
      def resolve_existing_ancestor(path)
        path.realpath
      rescue Errno::ENOENT
        return path if path.parent == path

        resolve_existing_ancestor(path.parent).join(path.basename)
      end

      sig { params(path: String).returns(T::Boolean) }
      def absolute_path?(path)
        path.start_with?("/")
      end

      sig { params(path: String).returns(T::Boolean) }
      def relative_replacement_path?(path)
        # https://golang.org/ref/mod#go-mod-file-replace
        [".", ".."].include?(path) || path.start_with?("./", "../")
      end

      sig { params(directory: T.nilable(String)).returns(Pathname) }
      def module_pathname(directory)
        @repo_contents_path.join(T.must(directory).sub(%r{^/}, ""))
      end

      sig { params(path: String, kind: String, on_error: ErrorHandler).returns(GoModManifest) }
      def parse_replacement_manifest(path, kind, on_error:)
        command = "go #{kind} edit -json"
        stdout, stderr, status = Dir.chdir(File.dirname(path)) { Open3.capture3(command) }
        on_error.call(stderr) unless status.success?

        relative = Pathname.new(path).realpath.relative_path_from(replacement_repo_root)
        GoModManifest.from_json(stdout, file_path: "/#{relative}", command: command)
      end

      sig { params(on_error: ErrorHandler).returns(T::Hash[String, String]) }
      def replacement_manifests(on_error:)
        paths = T.let({}, T::Hash[String, String])
        current = File.expand_path("go.mod")
        paths[current] = "mod" if File.file?(current)

        work_file, stderr, status = Open3.capture3("go env GOWORK")
        on_error.call(stderr) unless status.success?
        work_file = work_file.strip
        return paths if work_file.empty? || work_file == "off"

        work_file = File.expand_path(work_file)
        assert_manifest_in_repo(work_file)
        paths[work_file] = "work"
        GoWorkParser.use_paths(File.read(work_file)).each do |mod_path|
          manifest = File.expand_path(File.join(mod_path, "go.mod"), File.dirname(work_file))
          next unless File.file?(manifest)

          assert_manifest_in_repo(manifest)
          paths[manifest] = "mod"
        end
        paths
      end

      sig { returns(Pathname) }
      def replacement_repo_root
        @repo_contents_path
      end

      sig { params(path: String).void }
      def assert_manifest_in_repo(path)
        root = replacement_repo_root
        resolved = Pathname.new(path).realpath
        return if resolved.to_s.start_with?("#{root}/")

        raise Dependabot::DependencyFileNotResolvable, "Workspace manifest is outside the checkout: #{path}"
      end

      sig { params(stub_root: String, on_error: ErrorHandler).returns(T::Array[ReplacementBinding]) }
      def replacement_bindings(stub_root, on_error:)
        root = replacement_repo_root
        replacement_manifests(on_error: on_error).flat_map do |path, kind|
          manifest = parse_replacement_manifest(path, kind, on_error: on_error)
          directory = "/#{Pathname.new(File.dirname(path)).realpath.relative_path_from(root)}"
          substitutions = stub_paths(manifest, directory, stub_root: stub_root)
          manifest.replacements.filter_map do |replacement|
            stub = substitutions[replacement.new.path]
            next unless stub

            ReplacementBinding.new(
              manifest: path,
              kind: kind,
              old: replacement.old,
              original: replacement.new.path,
              stub: stub
            )
          end
        end
      end

      sig { params(bindings: T::Array[ReplacementBinding], restore: T::Boolean, on_error: ErrorHandler).void }
      def edit_replacement_bindings(bindings, restore:, on_error:)
        bindings.group_by(&:manifest).each do |path, entries|
          arguments = entries.map do |binding|
            old = [binding.old.path, binding.old.version].compact.join("@")
            target = restore ? binding.original : binding.stub
            "-replace=#{old}=#{target}"
          end
          command = Shellwords.join(["go", T.must(entries.first).kind, "edit"] + arguments + [path])
          _, stderr, status = Open3.capture3(command)
          on_error.call(stderr) unless status.success?
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
    end
  end
end
