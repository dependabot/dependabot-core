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
      DEPENDENCY_TYPES = %w(dependencies devDependencies optionalDependencies).freeze

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

      private

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
