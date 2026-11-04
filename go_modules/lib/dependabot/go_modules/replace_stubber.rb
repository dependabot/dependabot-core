# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/go_modules/go_mod_manifest"

module Dependabot
  module GoModules
    # Given a go.mod file, find all `replace` directives pointing to a path
    # on the local filesystem outside of the current checkout, and return a hash
    # mapping each original path to a temporary stub for its resolved target.
    #
    # This lets us substitute all parts of the go.mod that are dependent on
    # the layout of the filesystem with a structure we can reproduce (i.e.
    # no paths such as ../../../foo), run the Go tooling, then reverse the
    # process afterwards.
    class ReplaceStubber
      extend T::Sig

      sig { params(repo_contents_path: String, stub_root: String).void }
      def initialize(repo_contents_path, stub_root:)
        @repo_contents_path = T.let(Pathname.new(repo_contents_path).realpath, Pathname)
        @stub_root = stub_root
      end

      sig do
        params(manifest: GoModManifest, directory: T.nilable(String)).returns(T::Hash[String, String])
      end
      def stub_paths(manifest, directory)
        manifest.replacements
                .map { |replacement| replacement.new.path }
                .select { |p| stub_replace_path?(p, directory) }
                .to_h { |p| [p, File.join(@stub_root, Digest::SHA2.hexdigest(resolved_path(p, directory).to_s))] }
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
    end
  end
end
