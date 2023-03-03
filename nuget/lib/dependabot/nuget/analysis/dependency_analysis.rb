# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/version"
require "dependabot/nuget/native_helpers"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class DependencyAnalysis
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(DependencyAnalysis) }
      def self.from_json(json)
        Dependabot::Nuget::NativeHelpers.ensure_no_errors(json)

        updated_version = T.let(json.fetch("UpdatedVersion"), String)
        can_update = T.let(json.fetch("CanUpdate"), T::Boolean)
        version_comes_from_multi_dependency_property = T.let(json.fetch("VersionComesFromMultiDependencyProperty"),
                                                             T::Boolean)
        updated_dependencies = T.let(json.fetch("UpdatedDependencies"),
                                     T::Array[T::Hash[String, T.untyped]]).map do |dep|
          DependencyDetails.from_json(dep)
        end

        DependencyAnalysis.new(
          updated_version: updated_version,
          can_update: can_update,
          version_comes_from_multi_dependency_property: version_comes_from_multi_dependency_property,
          updated_dependencies: updated_dependencies
        )
      end

      sig do
        params(updated_version: String,
               can_update: T::Boolean,
               version_comes_from_multi_dependency_property: T::Boolean,
               updated_dependencies: T::Array[DependencyDetails]).void
      end
      def initialize(updated_version:, can_update:, version_comes_from_multi_dependency_property:,
                     updated_dependencies:)
        @updated_version = updated_version
        @can_update = can_update
        @version_comes_from_multi_dependency_property = version_comes_from_multi_dependency_property
        @updated_dependencies = updated_dependencies
      end

      sig { returns(String) }
      attr_reader :updated_version

      sig { returns(T::Boolean) }
      attr_reader :can_update

      sig { returns(T::Boolean) }
      attr_reader :version_comes_from_multi_dependency_property

      sig { returns(T::Array[DependencyDetails]) }
      attr_reader :updated_dependencies

      sig { returns(Dependabot::Nuget::Version) }
      def numeric_updated_version
        @numeric_updated_version ||= T.let(Version.new(updated_version), T.nilable(Dependabot::Nuget::Version))
      end
    end
  end
end
