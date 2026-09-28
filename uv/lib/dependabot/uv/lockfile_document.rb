# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency_file"

module Dependabot
  module Uv
    class LockfileDocument
      extend T::Sig

      LOCAL_SOURCE_KEYS = %w(virtual editable directory).freeze

      class GraphPackage < T::ImmutableStruct
        const :name, T.nilable(String)
        const :version, T.nilable(String)
        const :local_source, T::Boolean
        const :dependencies, T::Array[String]
        const :optional_dependencies, T::Array[String]
        const :dev_dependencies, T::Array[String]
      end

      sig { params(file: Dependabot::DependencyFile).returns(LockfileDocument) }
      def self.from_file(file)
        new(data: T.cast(TomlRB.parse(T.must(file.content)), Object), context: file.path)
      end

      sig { params(data: Object, context: String).void }
      def initialize(data:, context:)
        @context = context
        @data = T.let(object_hash(data), T::Hash[String, Object])
      end

      sig { returns(T::Array[String]) }
      def workspace_members
        manifest = @data["manifest"]
        return [] unless manifest.is_a?(Hash)

        members = T.cast(manifest["members"], Object)
        return [] unless members.is_a?(Array)

        members.filter_map { |member| string_or_nil(T.cast(member, Object)) }
      end

      sig { returns(T::Array[GraphPackage]) }
      def graph_packages
        package_entries.filter_map do |entry|
          next unless entry.is_a?(Hash)

          package = object_hash(entry)
          source = package["source"]
          GraphPackage.new(
            name: string_or_nil(package["name"]),
            version: string_or_nil(package["version"]),
            local_source: source.is_a?(Hash) && LOCAL_SOURCE_KEYS.any? { |key| source.key?(key) },
            dependencies: dependency_names(package["dependencies"]),
            optional_dependencies: grouped_dependency_names(package["optional-dependencies"]),
            dev_dependencies: grouped_dependency_names(package["dev-dependencies"])
          )
        end
      end

      private

      sig { returns(T::Array[Object]) }
      def package_entries
        packages = @data.fetch("package", [])
        raise TypeError, "#{@context} package must be an array" unless packages.is_a?(Array)

        packages.map { |entry| T.cast(entry, Object) }
      end

      sig { params(value: Object).returns(T::Hash[String, Object]) }
      def object_hash(value)
        raise TypeError, "#{@context} must be an object" unless value.is_a?(Hash)

        value.to_h do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{@context} keys must be strings" unless key.is_a?(String)

          [key, T.cast(raw_value, Object)]
        end
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      def string_or_nil(value)
        value if value.is_a?(String)
      end

      sig { params(entries: Object).returns(T::Array[String]) }
      def dependency_names(entries)
        return [] unless entries.is_a?(Array)

        entries.filter_map do |raw_entry|
          entry = T.cast(raw_entry, Object)
          name = entry.is_a?(Hash) ? T.cast(entry["name"], Object) : entry
          string_or_nil(name)
        end
      end

      sig { params(groups: Object).returns(T::Array[String]) }
      def grouped_dependency_names(groups)
        return [] unless groups.is_a?(Hash)

        groups.values.flat_map { |entries| dependency_names(T.cast(entries, Object)) }
      end
    end
  end
end
