# typed: strong
# frozen_string_literal: true

require "open3"
require "sorbet-runtime"

module Dependabot
  module ManifestSets
    # The blobs directly inside one set directory at a commit, read from Git rather than from fetched
    # files, so it also sees files the job's package manager never reads.
    class DirectoryListing < T::ImmutableStruct
      extend T::Sig

      OBJECT_ID = /\A(?:\h{40}|\h{64})\z/
      SYMLINK_MODE = "120000"

      # Canonical set directory: repository-relative, no leading or trailing slash, "." for the root.
      const :directory, String
      # Basename => lowercase blob OID of each regular file. Empty when the directory does not exist at the commit.
      const :blobs, T::Hash[String, String]
      # Basenames of symlinks, whose blob is the link text rather than the content a reader sees.
      const :symlinks, T::Array[String], default: []

      # Converts a job directory such as "/", "/api" or "/api/" into its canonical form ("." or "api"); the
      # canonical form maps to itself.
      # Returns nil for anything that is not a plain path inside the repository.
      sig { params(directory: String).returns(T.nilable(String)) }
      def self.normalize(directory)
        return nil unless directory.valid_encoding?

        trimmed = directory.delete_prefix("/").delete_suffix("/")
        return "." if trimmed.empty? || trimmed == "."
        return nil if trimmed.include?("\0") || trimmed.include?("\n")
        return nil if trimmed.split("/", -1).any? { |part| part.empty? || part == "." || part == ".." }

        trimmed
      end

      # Lists `directory` (canonical form) at `commit` in the checkout at `repo_contents_path`. Returns nil
      # when Git cannot answer or a name in the directory is not valid UTF-8, so callers never act on a
      # partial listing.
      sig do
        params(repo_contents_path: String, commit: String, directory: String).returns(T.nilable(DirectoryListing))
      end
      def self.read(repo_contents_path:, commit:, directory:)
        return nil unless commit.match?(OBJECT_ID) && normalize(directory) == directory

        prefix = directory == "." ? "" : "#{directory}/"
        env = { "GIT_LITERAL_PATHSPECS" => "1" }
        stdout, status =
          if prefix.empty?
            Open3.capture2(env, "git", "-C", repo_contents_path, "ls-tree", "-z", "--full-tree", commit, binmode: true)
          else
            Open3.capture2(
              env, "git", "-C", repo_contents_path, "ls-tree", "-z", "--full-tree", commit, "--", prefix, binmode: true
            )
          end
        return nil unless status.success?

        entries = parse(stdout, prefix)
        entries && build(directory, entries)
      end

      sig { params(directory: String, entries: T::Hash[String, [String, String]]).returns(DirectoryListing) }
      def self.build(directory, entries)
        symlinks, files = entries.partition { |_name, (mode, _oid)| mode == SYMLINK_MODE }
        new(
          directory: directory,
          blobs: files.to_h { |name, (_mode, oid)| [name, oid] },
          symlinks: symlinks.map(&:first)
        )
      end
      private_class_method :build

      # Each `ls-tree -z` entry is "<mode> <type> <oid>\t<path>\0"; returns basename => [mode, oid] per blob.
      sig { params(output: String, prefix: String).returns(T.nilable(T::Hash[String, [String, String]])) }
      def self.parse(output, prefix)
        output.split("\0").each_with_object({}) do |entry, blobs|
          meta, path = entry.split("\t", 2)
          mode, type, oid = meta.to_s.split
          next unless type == "blob"
          return nil unless path&.start_with?(prefix.b) && oid&.match?(OBJECT_ID)

          name = path.delete_prefix(prefix.b).force_encoding(Encoding::UTF_8)
          return nil if name.empty? || name.include?("/") || !name.valid_encoding?

          blobs[name] = [mode.to_s, oid.downcase]
        end
      end
      private_class_method :parse
    end
  end
end
