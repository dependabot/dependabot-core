# frozen_string_literal: true

module Dependabot
  module GoModules
    # Given a go.mod file, find all `replace` directives pointing to a path
    # on the local filesystem outside of the current checkout, and return a hash
    # mapping the original path to a hash of the path.
    #
    # This lets us substitute all parts of the go.mod that are dependent on
    # the layout of the filesystem with a structure we can reproduce (i.e.
    # no paths such as ../../../foo), run the Go tooling, then reverse the
    # process afterwards.
    class ReplaceStubber
      def initialize(repo_contents_path)
        @repo_contents_path = repo_contents_path
      end

      def stub_paths(manifest, directory)
        (manifest["Replace"] || []).
          filter_map { |r| r["New"]["Path"] }.
          select { |p| stub_replace_path?(p, directory) }.
          to_h { |p| [p, "./" + Digest::SHA2.hexdigest(p)] }
      end

      private

      def stub_replace_path?(path, directory)
        return true if absolute_path?(path)
        return false unless relative_replacement_path?(path)
        return true if @repo_contents_path.nil?

        resolved_path = module_pathname(directory).join(path).realpath
        inside_repo_contents_path = resolved_path.to_s.start_with?(@repo_contents_path.to_s)
        !inside_repo_contents_path
      rescue Errno::ENOENT
        true
      end

      def absolute_path?(path)
        path.start_with?("/")
      end

      def relative_replacement_path?(path)
        # https://golang.org/ref/mod#go-mod-file-replace
        path.start_with?("./") || path.start_with?("../")
      end

      def module_pathname(directory)
        @module_pathname ||= Pathname.new(@repo_contents_path).join(directory.sub(%r{^/}, ""))
      end
    end
  end
end
