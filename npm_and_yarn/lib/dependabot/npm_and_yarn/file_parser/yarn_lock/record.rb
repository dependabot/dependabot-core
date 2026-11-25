# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class YarnLock
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
            value = object["version"]
            return if value.nil?
            return value if value.is_a?(String)

            invalid!("#{@context}.version must be a string or nil")
          end

          sig { returns(Dependabot::Package::NpmLockfileDetails) }
          def lookup_details
            Dependabot::Package::NpmLockfileDetails.from_object(object, path: @path, context: @context)
          end

          sig { returns(T::Hash[String, String]) }
          def dependencies
            dependency_requirements || {}
          end

          sig { returns(T.nilable(T::Hash[String, String])) }
          def dependency_requirements
            requirement_map("dependencies")
          end

          sig { returns(T.nilable(T::Hash[String, String])) }
          def optional_dependencies
            requirement_map("optionalDependencies")
          end

          private

          sig { params(field: String).returns(T.nilable(T::Hash[String, String])) }
          def requirement_map(field)
            value = object[field]
            return if value.nil?

            invalid!("#{@context}.#{field} must be an object") unless value.is_a?(Hash)
            value.to_h do |raw_name, raw_requirement|
              name = T.cast(raw_name, Object)
              requirement = T.cast(raw_requirement, Object)
              invalid!("#{@context}.#{field} keys must be strings") unless name.is_a?(String)
              invalid!("#{@context}.#{field}.#{name} must be a string") unless requirement.is_a?(String)

              [name, requirement]
            end
          end

          sig { returns(ObjectHash) }
          def object
            return @object if @object

            data = @data
            invalid!("#{@context} must be an object") unless data.is_a?(Hash)

            @object = data.to_h do |raw_key, raw_value|
              key = T.cast(raw_key, Object)
              invalid!("#{@context} keys must be strings") unless key.is_a?(String)

              [key, T.cast(raw_value, Object)]
            end
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
