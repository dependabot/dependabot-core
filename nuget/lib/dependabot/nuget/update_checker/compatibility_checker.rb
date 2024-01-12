# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers/base"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class CompatibilityChecker
        require_relative "nuspec_fetcher"
        require_relative "nupkg_fetcher"
        require_relative "tfm_finder"
        require_relative "tfm_comparer"

        def initialize(dependency_urls:, dependency:, tfm_finder:)
          @dependency_urls = dependency_urls
          @dependency = dependency
          @tfm_finder = tfm_finder
        end

        def compatible?(version)
          nuspec_xml = NuspecFetcher.fetch_nuspec(dependency_urls, dependency.name, version)
          return false unless nuspec_xml

          # development dependencies are packages such as analyzers which need to be
          # compatible with the compiler not the project itself.
          return true if development_dependency?(nuspec_xml)

          package_tfms = parse_package_tfms(nuspec_xml)
          package_tfms = fetch_package_tfms(version) if package_tfms.empty?
          # nil is a special return value that indicates that the package is likely a development dependency
          return true if package_tfms.nil?
          return false if package_tfms.empty?

          return false if project_tfms.nil? || project_tfms.empty?

          TfmComparer.are_frameworks_compatible?(project_tfms, package_tfms)
        end

        private

        attr_reader :dependency_urls, :dependency, :tfm_finder

        def development_dependency?(nuspec_xml)
          contents = nuspec_xml.at_xpath("package/metadata/developmentDependency")&.content&.strip
          return false unless contents

          contents.casecmp("true").zero?
        end

        def parse_package_tfms(nuspec_xml)
          nuspec_xml.xpath("//dependencies/group").map do |group|
            group.attribute("targetFramework")
          end
        end

        def project_tfms
          return @project_tfms if defined?(@project_tfms)

          @project_tfms = tfm_finder.frameworks(dependency)
        end

        def fetch_package_tfms(dependency_version)
          nupkg_buffer = NupkgFetcher.fetch_nupkg_buffer(dependency_urls, dependency.name, dependency_version)
          return [] unless nupkg_buffer

          # Parse tfms from the folders beneath the lib folder
          folder_name = "lib/"
          tfms = Set.new
          Zip::File.open_buffer(nupkg_buffer) do |zip|
            lib_file_entries = zip.select { |entry| entry.name.start_with?(folder_name) }
            # If there is no lib folder in this package, assume it is a development dependency
            return nil if lib_file_entries.empty?

            lib_file_entries.each do |entry|
              _, tfm = entry.name.split("/").first(2)
              tfms << tfm
            end
          end
          tfms.to_a
        end
      end
    end
  end
end
