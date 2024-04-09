# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"

module Dependabot
  module Nuget
    class CompatibilityChecker
      extend T::Sig

      require_relative "nuspec_fetcher"
      require_relative "nupkg_fetcher"
      require_relative "tfm_finder"
      require_relative "tfm_comparer"

      sig do
        params(
          dependency_urls: T::Array[T::Hash[Symbol, String]],
          dependency: Dependabot::Dependency,
          tfm_finder: Dependabot::Nuget::TfmFinder
        ).void
      end
      def initialize(dependency_urls:, dependency:, tfm_finder:)
        @dependency_urls = dependency_urls
        @dependency = dependency
        @tfm_finder = tfm_finder
      end

      sig { params(version: String).returns(T::Boolean) }
      def compatible?(version)
        nuspec_xml = NuspecFetcher.fetch_nuspec(dependency_urls, dependency.name, version)
        return false unless nuspec_xml

        # development dependencies are packages such as analyzers which need to be compatible with the compiler not the
        # project itself, but some packages that report themselves as development dependencies still contain target
        # framework dependencies and should be checked for compatibility through the regular means
        return true if pure_development_dependency?(nuspec_xml)

        package_tfms = parse_package_tfms(nuspec_xml)
        package_tfms = fetch_package_tfms(version) if package_tfms.empty?
        # nil is a special return value that indicates that the package is likely a development dependency
        return true if package_tfms.nil?
        return false if package_tfms.empty?

        return false if project_tfms.nil? || project_tfms&.empty?

        TfmComparer.are_frameworks_compatible?(T.must(project_tfms), package_tfms)
      end

      private

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      attr_reader :dependency_urls

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(Dependabot::Nuget::TfmFinder) }
      attr_reader :tfm_finder

      sig { params(nuspec_xml: Nokogiri::XML::Document).returns(T::Boolean) }
      def pure_development_dependency?(nuspec_xml)
        contents = nuspec_xml.at_xpath("package/metadata/developmentDependency")&.content&.strip
        return false unless contents # no `developmentDependency` element

        self_reports_as_development_dependency = contents.casecmp?("true")
        return false unless self_reports_as_development_dependency

        # even though a package self-reports as a development dependency, it might not be if it has dependency groups
        # with a target framework
        dependency_groups_with_target_framework =
          nuspec_xml.at_xpath("/package/metadata/dependencies/group[@targetFramework]")
        dependency_groups_with_target_framework.to_a.empty?
      end

      sig { params(nuspec_xml: Nokogiri::XML::Document).returns(T::Array[String]) }
      def parse_package_tfms(nuspec_xml)
        nuspec_xml.xpath("//dependencies/group").filter_map { |group| group.attribute("targetFramework") }
      end

      sig { returns(T.nilable(T::Array[String])) }
      def project_tfms
        @project_tfms ||= T.let(tfm_finder.frameworks(dependency), T.nilable(T::Array[String]))
      end

      sig { params(dependency_version: String).returns(T.nilable(T::Array[String])) }
      def fetch_package_tfms(dependency_version)
        cache = CacheManager.cache("compatibility_checker_tfms_cache")
        key = "#{dependency.name}::#{dependency_version}"

        cache[key] ||= begin
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

              # some zip compressors create empty directory entries (in this case `lib/`) which can cause the string
              # split to return `nil`, so we have to explicitly guard against that
              tfms << tfm if tfm
            end
          end

          tfms.to_a
        end

        cache[key]
      end
    end
  end
end
