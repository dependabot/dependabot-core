# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/package/npm_package_manager_config"

module Dependabot
  module Package
    class NpmPackageJson
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }
      CatalogEntries = T.type_alias { T::Hash[String, String] }
      DEPENDENCY_TYPES = %w(dependencies devDependencies optionalDependencies).freeze
      CATALOG_FIELDS = %w(catalog catalogs).freeze

      sig { params(file: DependencyFile).returns(NpmPackageJson) }
      def self.from_file(file)
        new(T.cast(JSON.parse(T.must(file.content)), Object), file.path)
      end

      sig { params(data: Object, path: String).void }
      def initialize(data, path)
        @path = path
        @data = T.let(object_hash(data, "root"), ObjectHash)
      end

      sig do
        params(_block: T.proc.params(name: String, requirement: String, type: String).void).void
      end
      def each_dependency(&_block)
        DEPENDENCY_TYPES.each do |type|
          dependencies = @data[type]
          next unless dependencies

          object_hash(dependencies, type).each do |name, requirement|
            next unless requirement.is_a?(String)

            yield name, requirement, type
          end
        end
      end

      sig { returns(T.nilable(String)) }
      def name
        value = @data["name"]
        value if value.is_a?(String)
      end

      sig { returns(T::Boolean) }
      def flat?
        !!@data["flat"]
      end

      sig { returns(T::Boolean) }
      def workspaces?
        !!@data["workspaces"]
      end

      sig { returns(NpmPackageManagerConfig) }
      def package_manager_config
        NpmPackageManagerConfig.from_package_json(@data)
      end

      # The default catalog that `catalog:` requirements resolve against.
      sig { returns(CatalogEntries) }
      def catalog
        prefix, fields = catalog_fields
        value = fields["catalog"]
        return {} unless value

        catalog_entries(value, "#{prefix}catalog")
      end

      # Named catalogs that `catalog:<name>` requirements resolve against,
      # keyed by catalog name. `default` extends the default catalog.
      sig { returns(T::Hash[String, CatalogEntries]) }
      def catalogs
        prefix, fields = catalog_fields
        value = fields["catalogs"]
        return {} unless value

        field = "#{prefix}catalogs"
        result = T.let({}, T::Hash[String, CatalogEntries])
        object_hash(value, field).each do |name, entries|
          result[name] = catalog_entries(entries, "#{field}.#{name}")
        end
        result
      end

      # The key of the object Bun reads both catalog fields from, or nil for
      # the root. Bun reads them from `workspaces` when it declares either of
      # them, and ignores the root fields in that case.
      sig { returns(T.nilable(String)) }
      def catalog_container
        workspaces = @data["workspaces"]
        return unless workspaces.is_a?(Hash)

        "workspaces" if CATALOG_FIELDS.any? { |field| object_hash(workspaces, "workspaces").key?(field) }
      end

      private

      sig { returns([String, ObjectHash]) }
      def catalog_fields
        container = catalog_container
        return ["", @data] unless container

        ["#{container}.", object_hash(@data[container], container)]
      end

      sig { params(value: Object, field: String).returns(CatalogEntries) }
      def catalog_entries(value, field)
        entries = T.let({}, CatalogEntries)
        object_hash(value, field).each do |name, requirement|
          entries[name] = requirement if requirement.is_a?(String)
        end
        entries
      end

      sig { params(value: Object, field: String).returns(ObjectHash) }
      def object_hash(value, field)
        raise TypeError, "#{@path}: #{field} must be an object" unless value.is_a?(Hash)

        result = T.let({}, ObjectHash)
        value.each do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{@path}: #{field} keys must be strings" unless key.is_a?(String)

          result[key] = T.cast(raw_value, Object)
        end
        result
      end
    end
  end
end
