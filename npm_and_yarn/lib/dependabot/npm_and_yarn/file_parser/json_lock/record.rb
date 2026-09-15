# typed: strong
# frozen_string_literal: true

require "uri"
require "sorbet-runtime"
require "dependabot/npm_and_yarn/file_parser/json_lock"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class JsonLock
        class Record
          extend T::Sig

          ObjectHash = T.type_alias { T::Hash[String, Object] }

          sig { params(data: Object, path: String, context: String).void }
          def initialize(data, path:, context:)
            @data = data
            @path = path
            @context = context
            @object = T.let(nil, T.nilable(ObjectHash))
          end

          sig { returns(T.nilable(String)) }
          def version
            optional_string("version")
          end

          sig { returns(T.nilable(String)) }
          def name
            optional_string("name")
          end

          sig { returns(T.nilable(String)) }
          def resolved
            optional_string("resolved")
          end

          sig { returns(T.nilable(String)) }
          def resolution
            optional_string("resolution")
          end

          sig { returns(T::Boolean) }
          def dev?
            boolean("dev")
          end

          sig { returns(T::Boolean) }
          def bundled?
            boolean("bundled")
          end

          sig { returns(T::Hash[String, Record]) }
          def dependency_entries
            field = object["dependencies"] ? "dependencies" : "packages"
            context = "#{@context}.#{field}"
            mapping = object_value(object.fetch(field, {}), context)

            # Modern package records contain requirement strings rather than nested lock entries.
            mapping.reject { |_, value| value.is_a?(String) }.to_h do |key, data|
              [key, self.class.new(data, path: @path, context: "#{context}.#{key}")]
            end
          end

          sig { returns(T::Hash[String, Record]) }
          def legacy_entries
            entries(object.fetch("dependencies", {}), "#{@context}.dependencies")
          end

          sig { params(name: String).returns(T.nilable(Record)) }
          def legacy_entry(name)
            dependencies = object["dependencies"]
            return if dependencies.nil?

            data = object_value(dependencies, "#{@context}.dependencies")[name]
            self.class.new(data, path: @path, context: "dependencies.#{name}") unless data.nil?
          end

          sig { params(primary: String, fallback: String).returns(T.nilable(Record)) }
          def package_entry(primary, fallback)
            packages = object["packages"]
            return if packages.nil?

            mapping = object_value(packages, "#{@context}.packages")
            key = mapping[primary] ? primary : fallback
            data = mapping[key]
            self.class.new(data, path: @path, context: "packages.#{key}") unless data.nil?
          end

          sig { params(default_registry: String).returns(T.nilable(URI::Generic)) }
          def registry_uri(default_registry)
            value = object.fetch("resolved", default_registry)
            # Registry inference filters invalid URIs, including non-string values.
            return unless value.is_a?(String)

            URI.parse(value)
          rescue URI::InvalidURIError
            nil
          end

          private

          sig { returns(ObjectHash) }
          def object
            @object ||= object_value(@data, @context)
          end

          sig { params(value: Object, context: String).returns(ObjectHash) }
          def object_value(value, context)
            invalid!("#{context} must be an object") unless value.is_a?(Hash)

            value.to_h do |raw_key, raw_value|
              key = T.cast(raw_key, Object)
              invalid!("#{context} keys must be strings") unless key.is_a?(String)

              [key, T.cast(raw_value, Object)]
            end
          end

          sig { params(value: Object, context: String).returns(T::Hash[String, Record]) }
          def entries(value, context)
            object_value(value, context).to_h do |key, data|
              [key, self.class.new(data, path: @path, context: "#{context}.#{key}")]
            end
          end

          sig { params(key: String).returns(T.nilable(String)) }
          def optional_string(key)
            value = object[key]
            return if value.nil?
            return value if value.is_a?(String)

            invalid!("#{@context}.#{key} must be a string or nil")
          end

          sig { params(key: String).returns(T::Boolean) }
          def boolean(key)
            value = object[key]
            return false if value.nil? || value == false
            return true if value == true

            invalid!("#{@context}.#{key} must be a boolean or nil")
          end

          sig { params(message: String).returns(T.noreturn) }
          def invalid!(message)
            raise DependencyFileNotParseable.new(@path, message)
          end
        end
      end
    end
  end
end
