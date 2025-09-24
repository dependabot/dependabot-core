# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/conda/python_package_classifier"
require "dependabot/python/metadata_finder"

module Dependabot
  module Conda
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        return super unless python_package?(dependency.name)

        # Delegate to Python metadata finder for enhanced PyPI-based homepage URLs
        python_metadata_finder.homepage_url
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return nil unless python_package?(dependency.name)

        # Delegate to Python metadata finder for Python packages
        python_metadata_finder.send(:look_up_source)
      end

      sig { params(package_name: String).returns(T::Boolean) }
      def python_package?(package_name)
        PythonPackageClassifier.python_package?(package_name)
      end

      sig { returns(Dependabot::Python::MetadataFinder) }
      def python_metadata_finder
        # Cache the Python metadata finder instance for reuse across method calls
        # Credentials are passed through as-is since conda manifests don't specify pip-index credentials
        # TODO: If we decide to support non python packages for Conda we will have to review this
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
              file: req[:file]&.gsub(/environment\.ya?ml/, "requirements.txt"),
              source: nil # No private pip-index in conda manifests
            )
          end,
          package_manager: "pip"
        )
      end
    end
  end
end

Dependabot::MetadataFinders.register("conda", Dependabot::Conda::MetadataFinder)
