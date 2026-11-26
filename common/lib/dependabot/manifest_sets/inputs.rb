# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"

module Dependabot
  module ManifestSets
    # A repository file that determined a directory's resolved dependencies, identified by its
    # repository-relative path and the Git blob it had at the scanned commit.
    class InputFile < T::ImmutableStruct
      const :path, String
      const :blob_oid, String
    end

    # The provenance handed from a dependency grapher to submission code: either the complete list of
    # original repository inputs, or the reason a complete list could not be produced. Never a partial list.
    class Inputs < T::ImmutableStruct
      extend T::Sig

      # A dependency file that cannot be traced to a blob at the scanned commit, for example because no
      # checkout is available or the file only exists in the fetched content.
      UNKNOWN_PROVENANCE = "unknown_provenance"

      const :files, T::Array[InputFile], default: []
      const :unresolvable_reason, T.nilable(String), default: nil

      sig { returns(T::Boolean) }
      def resolved?
        unresolvable_reason.nil?
      end

      # Adds `extra` files, deduplicating by path. A path seen with two different blobs cannot describe one
      # commit, so the result becomes unresolvable rather than picking one.
      sig { params(extra: T::Array[InputFile]).returns(Inputs) }
      def with_files(extra)
        return self unless resolved?

        by_path = T.let({}, T::Hash[String, String])
        (files + extra).each do |file|
          known = by_path[file.path]
          return Inputs.unresolvable(UNKNOWN_PROVENANCE) if known && known != file.blob_oid

          by_path[file.path] = file.blob_oid
        end
        merged = by_path.map { |path, oid| InputFile.new(path: path, blob_oid: oid) }
        Inputs.new(files: merged.sort_by { |file| file.path.b })
      end

      sig { params(reason: String).returns(Inputs) }
      def self.unresolvable(reason)
        new(unresolvable_reason: reason)
      end

      # Looks up the original blob of each dependency file at `commit` in the checkout at
      # `repo_contents_path`, so the result describes repository content rather than anything rewritten
      # during fetching or resolution. Paths are deduplicated and sorted by bytes. Symlinked inputs are
      # unknown provenance: the link and every target it resolves through would all have to be recorded.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          repo_contents_path: T.nilable(String),
          commit: String
        ).returns(Inputs)
      end
      def self.resolve(dependency_files:, repo_contents_path:, commit:)
        return unresolvable(UNKNOWN_PROVENANCE) if repo_contents_path.nil?
        return unresolvable(UNKNOWN_PROVENANCE) if dependency_files.any?(&:symlink_target)

        paths = dependency_files.map(&:realpath).uniq
        return unresolvable(UNKNOWN_PROVENANCE) unless paths.all? { |path| batch_safe?(path) }

        oids = blob_oids(repo_contents_path, commit, paths)
        return unresolvable(UNKNOWN_PROVENANCE) if oids.nil?

        files = paths.zip(oids).map { |path, oid| InputFile.new(path: path, blob_oid: T.must(oid)) }
        new(files: files.sort_by { |file| file.path.b })
      end

      # `git ls-tree -z` separates entries with NUL, so a path must not contain one; a newline would also be
      # ambiguous in a path list, and anything escaping the repository root has no blob either.
      sig { params(path: String).returns(T::Boolean) }
      def self.batch_safe?(path)
        !path.empty? && !path.include?("\n") && !path.include?("\0") &&
          path != ".." && !path.start_with?("../", "/")
      end
      private_class_method :batch_safe?

      # A full SHA-1 or SHA-256 object ID.
      OBJECT_ID = /\A(?:\h{40}|\h{64})\z/

      # Mode of a regular (possibly executable) file in a Git tree; symlinks (120000) and submodules differ.
      REGULAR_FILE_MODES = %w(100644 100755).freeze

      # Returns one blob OID per path, in order, or nil if any path is not a regular file at `commit`. A path
      # through a symlinked directory is not in the tree, so it is reported missing rather than followed.
      sig do
        params(repo_contents_path: String, commit: String, paths: T::Array[String])
          .returns(T.nilable(T::Array[String]))
      end
      def self.blob_oids(repo_contents_path, commit, paths)
        return [] if paths.empty?

        entries = tree_entries(repo_contents_path, commit, paths)
        return nil if entries.nil?

        paths.map do |path|
          mode, type, oid = entries[path]
          return nil unless REGULAR_FILE_MODES.include?(mode) && type == "blob"
          return nil unless oid&.match?(OBJECT_ID)

          oid.downcase
        end
      end
      private_class_method :blob_oids

      # Upper bound on the path bytes passed to one `git ls-tree`, well below the operating system's
      # argument-size limit, so any number of inputs can be looked up.
      MAX_ARGUMENT_BYTES = T.let(64 * 1024, Integer)

      # Maps each listed path to its `[mode, type, oid]` at `commit`, or returns nil if Git cannot list them.
      # `ls-tree` matches each path literally (no globbing) from the tree root and does not follow symlinks.
      sig do
        params(repo_contents_path: String, commit: String, paths: T::Array[String])
          .returns(T.nilable(T::Hash[String, T::Array[String]]))
      end
      def self.tree_entries(repo_contents_path, commit, paths)
        # The commit precedes `--` on the command line, so it must not be readable as an option.
        return nil unless commit.match?(OBJECT_ID)

        entries = T.let({}, T::Hash[String, T::Array[String]])
        argument_batches(paths).each do |batch|
          command = ["git", "-C", repo_contents_path, "ls-tree", "-z", "--full-tree", commit, "--", *batch]
          stdout = IO.popen(command, "rb", err: File::NULL, &:read)
          return nil unless Process.last_status&.success?

          stdout.split("\0").each do |entry|
            meta, path = entry.split("\t", 2)
            entries[path.to_s.force_encoding(Encoding::UTF_8)] = meta.to_s.split(" ", 3)
          end
        end
        entries
      end
      private_class_method :tree_entries

      # Splits `paths` into consecutive batches of at most MAX_ARGUMENT_BYTES each (counting a terminator per
      # path); every batch holds at least one path.
      sig { params(paths: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def self.argument_batches(paths)
        batches = T.let([[]], T::Array[T::Array[String]])
        size = 0
        paths.each do |path|
          bytes = path.bytesize + 1
          if size + bytes > MAX_ARGUMENT_BYTES && !T.must(batches.last).empty?
            batches << []
            size = 0
          end
          T.must(batches.last) << path
          size += bytes
        end
        batches
      end
      private_class_method :argument_batches
    end
  end
end
