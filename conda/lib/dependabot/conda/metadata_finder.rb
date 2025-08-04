# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/conda/python_package_classifier"

module Dependabot
  module Conda
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def source
        # For Python packages in conda, delegate to Python metadata finder infrastructure
        return nil unless python_package?(dependency.name)

        # Would delegate to Python metadata finder logic here
        nil
      end

      private

      sig { params(package_name: String).returns(T::Boolean) }
      def python_package?(package_name)
        PythonPackageClassifier.python_package?(package_name)
      end
    end
  end
end

Dependabot::MetadataFinders.register("conda", Dependabot::Conda::MetadataFinder)
