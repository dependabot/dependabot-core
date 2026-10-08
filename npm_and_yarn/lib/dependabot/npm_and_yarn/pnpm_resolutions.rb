# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

module Dependabot
  module NpmAndYarn
    # Where a package resolves in a pnpm lockfile, dependent by dependent.
    #
    # A package can resolve to several versions at once when its dependents
    # declare ranges no single version satisfies, and an update can move any of
    # those edges, so two lockfiles are compared edge by edge rather than by the
    # set of versions they contain: an edge moved onto a version that was
    # already present elsewhere is a change too.
    class PnpmResolutions
      extend T::Sig

      SECTIONS = %w(importers packages snapshots).freeze
      DEPENDENCY_KEYS = %w(dependencies devDependencies optionalDependencies).freeze

      # The versions on edges to `name` that `after` has and `before` does not,
      # whether the edge changed version or is new.
      sig { params(before: String, after: String, name: String).returns(T::Array[String]) }
      def self.changed_versions(before, after, name)
        previous = new(before).edges(name)
        new(after).edges(name).reject { |edge, version| previous[edge] == version }.values.uniq
      end

      sig { params(content: String).void }
      def initialize(content)
        @content = content
        # pnpm 11+ can write an env document ahead of the project one.
        document = YAML.safe_load_stream(content).last
        @document = T.let(document.is_a?(Hash) ? document : {}, T::Hash[String, Object])
      end

      # The importer paths the lockfile records, as written.
      #
      # Read off the parse tree rather than the loaded document, because these
      # keys are directory names and Psych loads on the YAML 1.1 schema: a project
      # directory called `no`, `on`, `yes` or `10` arrives as a boolean or an
      # integer, and no spelling of those matches the directory the project sits
      # in. A lockfile that cannot be parsed at all raises on construction, as it
      # does for every other reader on this class.
      sig { returns(T::Array[String]) }
      def importers
        entries = value_for(root_mapping, "importers")
        return [] unless entries.is_a?(Psych::Nodes::Mapping)

        pairs(entries).filter_map { |key, _value| key.value if key.is_a?(Psych::Nodes::Scalar) }
      end

      # `dependent => version` for every edge to `name`.
      sig { params(name: String).returns(T::Hash[String, String]) }
      def edges(name)
        edges = T.let({}, T::Hash[String, String])
        # A single-project lockfile up to v6 keeps the root project's edges at the top level.
        collect(edges, "importers", ".", @document, name)
        SECTIONS.each do |section|
          entries = @document[section]
          next unless entries.is_a?(Hash)

          entries.each { |dependent, entry| collect(edges, section, dependent.to_s, entry, name) }
        end
        edges
      end

      sig { params(name: String).returns(T::Array[String]) }
      def versions(name)
        edges(name).values.uniq
      end

      private

      # The last document's root mapping, for the same reason the loaded document
      # is taken from the end of the stream.
      sig { returns(T.nilable(Psych::Nodes::Mapping)) }
      def root_mapping
        roots = Psych.parse_stream(@content).children.filter_map(&:root)
        roots.reverse.find { |node| node.is_a?(Psych::Nodes::Mapping) }
      end

      sig { params(mapping: T.nilable(Psych::Nodes::Mapping), key: String).returns(T.nilable(Psych::Nodes::Node)) }
      def value_for(mapping, key)
        return nil unless mapping

        pairs(mapping).each do |name, value|
          return value if name.is_a?(Psych::Nodes::Scalar) && name.value == key
        end
        nil
      end

      sig { params(mapping: Psych::Nodes::Mapping).returns(T::Array[T::Array[Psych::Nodes::Node]]) }
      def pairs(mapping)
        mapping.children.each_slice(2).to_a
      end

      sig do
        params(edges: T::Hash[String, String], section: String, dependent: String, entry: Object, name: String).void
      end
      def collect(edges, section, dependent, entry, name)
        return unless entry.is_a?(Hash)

        DEPENDENCY_KEYS.each do |key|
          declared = entry[key]
          next unless declared.is_a?(Hash) && declared.key?(name)

          edges["#{section}/#{dependent}/#{key}"] = version_of(declared[name])
        end
      end

      # A resolution is a version, a version with a peer suffix such as
      # `1.2.3(react@18.0.0)`, or an importer entry `{specifier:, version:}`.
      sig { params(resolution: Object).returns(String) }
      def version_of(resolution)
        value = resolution.is_a?(Hash) ? resolution["version"] : resolution
        value.to_s.sub(/\(.*\z/, "")
      end
    end
  end
end
