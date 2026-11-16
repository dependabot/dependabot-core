# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bundler/update_checker"
require "dependabot/dependency"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class ForceUpdateResult
        extend T::Sig

        class InvalidResult < SharedHelpers::HelperSubprocessFailed; end

        class Update < T::ImmutableStruct
          const :dependency, Dependabot::Dependency
          const :version, Gem::Version
        end

        ObjectHash = T.type_alias { T::Hash[String, Object] }

        sig { params(result: Object, dependencies: T::Array[Dependabot::Dependency]).returns(T::Array[Update]) }
        def self.from_helper_result(result, dependencies:)
          parts = array(result, "")
          updated = array(parts[0], "[0]")
          specs = array(parts[1], "[1]")
          updated.filter_map do |value|
            name = string(object(value, "updated dependency")["name"], "updated dependency.name")
            dependency = dependencies.find { |candidate| candidate.name == name }
            next unless dependency

            spec = spec_for(specs, name)
            Update.new(dependency: dependency, version: version(spec["version"]))
          end
        end

        sig { params(specs: T::Array[Object], name: String).returns(ObjectHash) }
        def self.spec_for(specs, name)
          specs.each do |value|
            fields = object(value, "spec")
            return fields if string(fields["name"], "spec.name") == name
          end
          invalid!(" has no resolved spec for #{name}")
        end
        private_class_method :spec_for

        sig { params(value: Object).returns(Gem::Version) }
        def self.version(value)
          Gem::Version.new(string(value, "spec.version"))
        rescue ArgumentError
          invalid!(".spec.version must be a valid gem version")
        end
        private_class_method :version

        sig { params(value: Object, field: String).returns(T::Array[Object]) }
        def self.array(value, field)
          invalid!("#{field} must be an array") unless value.is_a?(Array)

          value.map { |entry| T.cast(entry, Object) }
        end
        private_class_method :array

        sig { params(value: Object, field: String).returns(ObjectHash) }
        def self.object(value, field)
          invalid!(".#{field} must be an object") unless value.is_a?(Hash)

          value.to_h do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            invalid!(".#{field} keys must be strings") unless key.is_a?(String)

            [key, T.cast(raw_value, Object)]
          end
        end
        private_class_method :object

        sig { params(value: Object, field: String).returns(String) }
        def self.string(value, field)
          return value if value.is_a?(String)

          invalid!(".#{field} must be a string")
        end
        private_class_method :string

        sig { params(message: String).returns(T.noreturn) }
        def self.invalid!(message)
          raise InvalidResult.new(
            message: "force_update result#{message}",
            error_class: "TypeError",
            error_context: { function: "force_update" }
          ),
                cause: nil
        end
        private_class_method :invalid!
      end
    end
  end
end
