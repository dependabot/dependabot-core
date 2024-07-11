# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/native_discovery/native_evaluation_details"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeDependencyDetails
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(NativeDependencyDetails) }
      def self.from_json(json)
        name = T.let(json.fetch("Name"), String)
        version = T.let(json.fetch("Version"), T.nilable(String))
        type = T.let(json.fetch("Type"), String)
        evaluation = NativeEvaluationDetails
                     .from_json(T.let(json.fetch("EvaluationResult"), T.nilable(T::Hash[String, T.untyped])))
        target_frameworks = T.let(json.fetch("TargetFrameworks"), T.nilable(T::Array[String]))
        is_dev_dependency = T.let(json.fetch("IsDevDependency"), T::Boolean)
        is_direct = T.let(json.fetch("IsDirect"), T::Boolean)
        is_transitive = T.let(json.fetch("IsTransitive"), T::Boolean)
        is_override = T.let(json.fetch("IsOverride"), T::Boolean)
        is_update = T.let(json.fetch("IsUpdate"), T::Boolean)
        info_url = T.let(json.fetch("InfoUrl"), T.nilable(String))

        NativeDependencyDetails.new(name: name,
                                    version: version,
                                    type: type,
                                    evaluation: evaluation,
                                    target_frameworks: target_frameworks,
                                    is_dev_dependency: is_dev_dependency,
                                    is_direct: is_direct,
                                    is_transitive: is_transitive,
                                    is_override: is_override,
                                    is_update: is_update,
                                    info_url: info_url)
      end

      sig do
        params(name: String,
               version: T.nilable(String),
               type: String,
               evaluation: T.nilable(NativeEvaluationDetails),
               target_frameworks: T.nilable(T::Array[String]),
               is_dev_dependency: T::Boolean,
               is_direct: T::Boolean,
               is_transitive: T::Boolean,
               is_override: T::Boolean,
               is_update: T::Boolean,
               info_url: T.nilable(String)).void
      end
      def initialize(name:, version:, type:, evaluation:, target_frameworks:, is_dev_dependency:, is_direct:,
                     is_transitive:, is_override:, is_update:, info_url:)
        @name = name
        @version = version
        @type = type
        @evaluation = evaluation
        @target_frameworks = target_frameworks
        @is_dev_dependency = is_dev_dependency
        @is_direct = is_direct
        @is_transitive = is_transitive
        @is_override = is_override
        @is_update = is_update
        @info_url = info_url
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :version

      sig { returns(String) }
      attr_reader :type

      sig { returns(T.nilable(NativeEvaluationDetails)) }
      attr_reader :evaluation

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :target_frameworks

      sig { returns(T::Boolean) }
      attr_reader :is_dev_dependency

      sig { returns(T::Boolean) }
      attr_reader :is_direct

      sig { returns(T::Boolean) }
      attr_reader :is_transitive

      sig { returns(T::Boolean) }
      attr_reader :is_override

      sig { returns(T::Boolean) }
      attr_reader :is_update

      sig { returns(T.nilable(String)) }
      attr_reader :info_url
    end
  end
end
