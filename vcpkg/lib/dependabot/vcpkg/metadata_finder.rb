# typed: strict
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
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url =
          if info.nil?
            VCPKG_DEFAULT_BASELINE_URL
          else
            info[:url] || info.fetch("url", VCPKG_DEFAULT_BASELINE_URL)
          end
        Source.from_url(url)
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
