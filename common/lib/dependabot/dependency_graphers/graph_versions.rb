# typed: strict
# frozen_string_literal: true

require "digest"
require "json"
require "sorbet-runtime"

module Dependabot
  module DependencyGraphers
    # Each package manager that owns manifest sets reports an opaque graph version alongside its
    # submissions. Downstream consumers may reuse a graph only while the inputs and this version are both
    # unchanged, so the version must change whenever the grapher could produce a different graph for the
    # same inputs.
    #
    # graph_versions.json pins each owner's version to a sha256 of the sources that shape its graph output.
    # Each ecosystem's grapher spec fails when those sources change and the lock is not refreshed;
    # bin/update-manifest-set-graph-versions.rb refreshes it and makes the author decide whether to bump.
    module GraphVersions
      extend T::Sig

      class InvalidLock < StandardError; end

      class Entry < T::Struct
        const :graph_version, String
        const :sources, T::Array[String]
        const :sources_sha256, String
      end

      SCHEMA_VERSION = 1
      LOCK_PATH = T.let(File.expand_path("graph_versions.json", __dir__).freeze, String)
      REPO_ROOT = T.let(File.expand_path("../../../..", __dir__).freeze, String)
      SHA256 = /\A[0-9a-f]{64}\z/
      SOURCE_PATTERN = %r{\A(?:[A-Za-z0-9_.*-]+/)*[A-Za-z0-9_.*-]+\z}
      DOT_SEGMENTS = %w(. ..).freeze

      @entries = T.let(nil, T.nilable(T::Hash[String, Entry]))

      # The graph version core reports for `owner`, for example "pip".
      sig { params(owner: String).returns(String) }
      def self.for(owner)
        entry = entries[owner]
        raise ArgumentError, "no graph version is locked for #{owner.inspect}" unless entry

        entry.graph_version
      end

      sig { returns(T::Hash[String, Entry]) }
      def self.entries
        @entries ||= parse(File.read(LOCK_PATH, encoding: "UTF-8"))
      end

      sig { params(text: String).returns(T::Hash[String, Entry]) }
      def self.parse(text)
        document = JSON.parse(text)
        invalid!("expected an object with schema_version and owners") unless document.is_a?(Hash)
        invalid!("unknown fields") unless document.keys.sort == %w(owners schema_version)
        invalid!("unsupported schema_version") unless document["schema_version"] == SCHEMA_VERSION

        owners = document["owners"]
        invalid!("owners must be a non-empty object") unless owners.is_a?(Hash) && !owners.empty?

        owners.to_h { |owner, entry| [owner, parse_entry(owner, entry)] }
      rescue JSON::ParserError => e
        invalid!(e.message)
      end

      sig { params(entries: T::Hash[String, Entry]).returns(String) }
      def self.render(entries)
        owners = entries.keys.sort_by(&:b).to_h do |owner|
          entry = T.must(entries[owner])
          [owner, {
            "graph_version" => entry.graph_version,
            "sources" => entry.sources,
            "sources_sha256" => entry.sources_sha256
          }]
        end
        "#{JSON.pretty_generate({ 'schema_version' => SCHEMA_VERSION, 'owners' => owners })}\n"
      end

      # Repository-relative files matched by `sources`, sorted by bytes. Every pattern must match a file, so a
      # renamed source cannot silently drop out of the digest.
      sig { params(sources: T::Array[String], root: String).returns(T::Array[String]) }
      def self.source_files(sources, root: REPO_ROOT)
        sources.flat_map do |pattern|
          matches = Dir.glob(pattern, base: root).select { |path| File.file?(File.join(root, path)) }
          raise InvalidLock, "source pattern #{pattern.inspect} matches no files" if matches.empty?

          matches
        end.uniq.sort_by(&:b)
      end

      sig { params(sources: T::Array[String], root: String).returns(String) }
      def self.sources_sha256(sources, root: REPO_ROOT)
        listing = source_files(sources, root: root).map do |path|
          "#{path}\0#{Digest::SHA256.file(File.join(root, path)).hexdigest}\n"
        end
        Digest::SHA256.hexdigest(listing.join)
      end

      # Owners whose sources no longer match the locked digest.
      sig do
        params(entries: T::Hash[String, Entry], owners: T::Array[String], root: String).returns(T::Array[String])
      end
      def self.stale_owners(entries: self.entries, owners: entries.keys, root: REPO_ROOT)
        owners.reject do |owner|
          entry = entries.fetch(owner)
          sources_sha256(entry.sources, root: root) == entry.sources_sha256
        end
      end

      sig { params(owner: String, entry: T.anything).returns(Entry) }
      private_class_method def self.parse_entry(owner, entry)
        entry = case entry
                when Hash then entry
                else invalid!("#{owner}: expected an object")
                end
        invalid!("#{owner}: unknown fields") unless entry.keys.sort == %w(graph_version sources sources_sha256)

        Entry.new(
          graph_version: graph_version(owner, entry["graph_version"]),
          sources: sources(owner, entry["sources"]),
          sources_sha256: digest(owner, entry["sources_sha256"])
        )
      end

      sig { params(owner: String, value: T.anything).returns(String) }
      private_class_method def self.graph_version(owner, value)
        case value
        when String then return value unless value.empty?
        end

        invalid!("#{owner}: graph_version must be a non-empty string")
      end

      sig { params(owner: String, value: T.anything).returns(T::Array[String]) }
      private_class_method def self.sources(owner, value)
        case value
        when Array
          return value if !value.empty? && value.all? { |source| source.is_a?(String) && valid_source?(source) }
        end

        invalid!("#{owner}: sources must be non-empty repository-relative paths or globs")
      end

      sig { params(owner: String, value: T.anything).returns(String) }
      private_class_method def self.digest(owner, value)
        case value
        when String then return value if value.match?(SHA256)
        end

        invalid!("#{owner}: sources_sha256 must be a sha256 hex digest")
      end

      sig { params(source: String).returns(T::Boolean) }
      private_class_method def self.valid_source?(source)
        source.match?(SOURCE_PATTERN) && !source.split("/").intersect?(DOT_SEGMENTS)
      end

      sig { params(message: String).returns(T.noreturn) }
      private_class_method def self.invalid!(message)
        raise InvalidLock, "invalid graph version lock: #{message}"
      end
    end
  end
end
