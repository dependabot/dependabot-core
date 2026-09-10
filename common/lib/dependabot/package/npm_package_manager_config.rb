# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Package
    class NpmPackageManagerConfig < T::ImmutableStruct
      extend T::Sig

      ObjectHash = T.type_alias { T::Hash[String, Object] }

      const :package_manager, T.nilable(String), default: nil
      const :engines, T.nilable(T::Hash[String, String]), default: nil

      sig { params(package_json: T.nilable(Object)).returns(NpmPackageManagerConfig) }
      def self.from_package_json(package_json)
        return new if package_json.nil?

        manifest = object_hash(package_json, "package.json")

        new(
          package_manager: optional_string(manifest["packageManager"], "packageManager"),
          engines: parse_engines(manifest)
        )
      end

      sig { params(manifest: ObjectHash).returns(T.nilable(T::Hash[String, String])) }
      def self.parse_engines(manifest)
        return unless manifest.key?("engines")

        raw_engines = manifest["engines"]
        return if raw_engines.nil?

        engines = T.let({}, T::Hash[String, String])
        object_hash(raw_engines, "engines").each do |name, raw_requirement|
          next if raw_requirement.nil?

          raise TypeError, "engines.#{name} must be a string" unless raw_requirement.is_a?(String)

          engines[name] = raw_requirement
        end
        engines
      end
      private_class_method :parse_engines

      sig { params(value: Object, context: String).returns(ObjectHash) }
      def self.object_hash(value, context)
        raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

        result = T.let({}, ObjectHash)
        value.each do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

          result[key] = T.cast(raw_value, Object)
        end
        result
      end
      private_class_method :object_hash

      sig { params(value: T.nilable(Object), context: String).returns(T.nilable(String)) }
      def self.optional_string(value, context)
        return if value.nil?
        return value if value.is_a?(String)

        raise TypeError, "#{context} must be a string"
      end
      private_class_method :optional_string
    end
  end
end
