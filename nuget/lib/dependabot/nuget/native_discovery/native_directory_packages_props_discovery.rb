# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/native_discovery/native_dependency_details"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeDirectoryPackagesPropsDiscovery < NativeDependencyFileDiscovery
      extend T::Sig

      sig do
        override.params(json: T.nilable(T::Hash[String, T.untyped]),
                        directory: String).returns(T.nilable(NativeDirectoryPackagesPropsDiscovery))
      end
      def self.from_json(json, directory)
        return nil if json.nil?

        file_path = File.join(directory, T.let(json.fetch("FilePath"), String))
        is_transitive_pinning_enabled = T.let(json.fetch("IsTransitivePinningEnabled"), T::Boolean)
        dependencies = T.let(json.fetch("Dependencies"), T::Array[T::Hash[String, T.untyped]]).map do |dep|
          NativeDependencyDetails.from_json(dep)
        end

        NativeDirectoryPackagesPropsDiscovery.new(file_path: file_path,
                                                  is_transitive_pinning_enabled: is_transitive_pinning_enabled,
                                                  dependencies: dependencies)
      end

      sig do
        params(file_path: String,
               is_transitive_pinning_enabled: T::Boolean,
               dependencies: T::Array[NativeDependencyDetails]).void
      end
      def initialize(file_path:, is_transitive_pinning_enabled:, dependencies:)
        super(file_path: file_path, dependencies: dependencies)
        @is_transitive_pinning_enabled = is_transitive_pinning_enabled
      end

      sig { returns(T::Boolean) }
      attr_reader :is_transitive_pinning_enabled
    end
  end
end
