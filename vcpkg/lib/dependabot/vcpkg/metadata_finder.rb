# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Vcpkg
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        # For individual VCPKG packages, try to find their specific homepage
        # If the dependency has a specific source URL, use that
        return source_url if source&.url != VCPKG_DEFAULT_BASELINE_URL.chomp(".git")

        # For the main VCPKG baseline dependency, return the VCPKG homepage
        if dependency.name == VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME
          "https://vcpkg.io"
        else
          # For individual packages, try to construct their VCPKG page URL
          "https://vcpkg.io/en/package/#{dependency.name}"
        end
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # Check if this is a Git dependency with a specific source
        info = dependency.requirements.filter_map(&:source).first

        url = source_string(info, "url") || VCPKG_DEFAULT_BASELINE_URL
        Source.from_url(url)
      end

      sig do
        params(
          source: T.nilable(Dependabot::DependencyRequirement::Details),
          key: String
        ).returns(T.nilable(String))
      end
      def source_string(source, key)
        return unless source

        value = source[key] || source[key.to_sym]
        value if value.is_a?(String)
      end

      sig { override.returns(T.nilable(String)) }
      def suggested_changelog_url
        # For the main VCPKG baseline dependency, point to releases
        return unless dependency.name == VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME

        "#{VCPKG_DEFAULT_BASELINE_URL}/releases"
      end
    end
  end
end

Dependabot::MetadataFinders.register("vcpkg", Dependabot::Vcpkg::MetadataFinder)
