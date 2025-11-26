# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/python/metadata_finder"

module Dependabot
  module Conda
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        return python_metadata_finder.homepage_url if pip_dependency?

        nil
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return python_metadata_finder.send(:look_up_source) if pip_dependency?

        nil
      end

      sig { returns(T::Boolean) }
      def pip_dependency?
        dependency.requirements.any? { |req| req[:groups]&.include?("pip") }
      end

      sig { returns(Dependabot::Python::MetadataFinder) }
      def python_metadata_finder
        @python_metadata_finder ||= T.let(
          Dependabot::Python::MetadataFinder.new(
            dependency: python_dependency,
            credentials: credentials
          ),
          T.nilable(Dependabot::Python::MetadataFinder)
        )
        @python_metadata_finder
      end

      sig { returns(Dependabot::Dependency) }
      def python_dependency
        Dependabot::Dependency.new(
          name: dependency.name,
          version: dependency.version,
          requirements: dependency.requirements.map do |req|
            req.merge(
              source: nil
            )
          end,
          package_manager: "pip"
        )
      end
    end
  end
end

Dependabot::MetadataFinders.register("conda", Dependabot::Conda::MetadataFinder)
