# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/julia/registry_client"

module Dependabot
  module Julia
    class MetadataFinder < Dependabot::MetadataFinders::Base
      def source_url
        source_url_from_dependency || source_url_from_registry || fallback_source_url
      end

      private

      def source_url_from_dependency
        dependency_source_url = dependency.requirements.filter_map { |r| r.dig(:source, :url) }.first
        return dependency_source_url if dependency_source_url
        return nil if dependency.requirements.empty?

        source = dependency.requirements.first[:source]
        source&.fetch(:url, nil)
      end

      def source_url_from_registry
        registry_client = Julia::RegistryClient.new(credentials)
        info = registry_client.fetch_package_info(dependency.name)
        return info["repo"] if info["repo"]
        nil
      rescue StandardError => e
        Dependabot.logger.warn("Error finding source URL from registry: #{e}")
        nil
      end

      def fallback_source_url
        # Julia packages often follow the convention of having a .jl suffix on GitHub
        # but that suffix isn't always included in the package name
        package_name = dependency.name.end_with?(".jl") ? dependency.name : "#{dependency.name}.jl"
        "https://github.com/JuliaLang/#{package_name}"
      end
    end
  end
end

Dependabot::MetadataFinders.register("julia", Dependabot::Julia::MetadataFinder)
