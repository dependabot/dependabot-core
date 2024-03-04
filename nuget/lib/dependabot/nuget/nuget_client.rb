# typed: strict
# frozen_string_literal: true

require "dependabot/nuget/cache_manager"
require "dependabot/nuget/http_response_helpers"
require "dependabot/nuget/update_checker/repository_finder"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NugetClient
      extend T::Sig

      sig do
        params(dependency_name: String, repository_details: T::Hash[Symbol, String])
          .returns(T.nilable(T::Set[String]))
      end
      def self.get_package_versions(dependency_name, repository_details)
        repository_type = repository_details.fetch(:repository_type)
        if repository_type == "v3"
          get_package_versions_v3(dependency_name, repository_details)
        elsif repository_type == "v2"
          get_package_versions_v2(dependency_name, repository_details)
        else
          raise "Unknown repository type: #{repository_type}"
        end
      end

      sig do
        params(dependency_name: String, repository_details: T::Hash[Symbol, String])
          .returns(T.nilable(T::Set[String]))
      end
      private_class_method def self.get_package_versions_v3(dependency_name, repository_details)
        # Use the registration URL if possible because it is fast and correct
        if repository_details[:registration_url]
          get_versions_from_registration_v3(repository_details)
        # use the search API if not because it is slow but correct
        elsif repository_details[:search_url]
          get_versions_from_search_url_v3(repository_details, dependency_name)
        # Otherwise, use the versions URL (fast but wrong because it includes unlisted versions)
        elsif repository_details[:versions_url]
          get_versions_from_versions_url_v3(repository_details)
        else
          raise "No version sources were available for #{dependency_name} in #{repository_details}"
        end
      end

      sig do
        params(dependency_name: String, repository_details: T::Hash[Symbol, String])
          .returns(T.nilable(T::Set[String]))
      end
      private_class_method def self.get_package_versions_v2(dependency_name, repository_details)
        doc = execute_xml_nuget_request(repository_details.fetch(:versions_url), repository_details)
        return unless doc

        # v2 APIs can differ, but all tested have this title value set to the name of the package
        title_nodes = doc.xpath("/feed/entry/title")
        matching_versions = Set.new
        title_nodes.each do |title_node|
          return nil unless title_node.text

          next unless title_node.text.casecmp?(dependency_name)

          version_node = title_node.parent.xpath("properties/Version")
          matching_versions << version_node.text if version_node && version_node.text
        end

        matching_versions
      end

      sig { params(repository_details: T::Hash[Symbol, String]).returns(T.nilable(T::Set[String])) }
      private_class_method def self.get_versions_from_versions_url_v3(repository_details)
        body = execute_json_nuget_request(repository_details.fetch(:versions_url), repository_details)
        ver_array = T.let(body&.fetch("versions"), T.nilable(T::Array[String]))
        ver_array&.to_set
      end

      sig { params(repository_details: T::Hash[Symbol, String]).returns(T.nilable(T::Set[String])) }
      private_class_method def self.get_versions_from_registration_v3(repository_details)
        url = repository_details.fetch(:registration_url)
        body = execute_json_nuget_request(url, repository_details)

        return unless body

        pages = body.fetch("items")
        versions = T.let(Set.new, T::Set[String])
        pages.each do |page|
          items = page["items"]
          if items
            # inlined entries
            get_versions_from_inline_page(items, versions)
          else
            # paged entries
            page_url = page["@id"]
            page_body = execute_json_nuget_request(page_url, repository_details)
            next unless page_body

            items = page_body.fetch("items")
            items.each do |item|
              catalog_entry = item.fetch("catalogEntry")
              versions << catalog_entry.fetch("version") if catalog_entry["listed"] == true
            end
          end
        end

        versions
      end

      sig { params(items: T::Array[T::Hash[String, T.untyped]], versions: T::Set[String]).void }
      private_class_method def self.get_versions_from_inline_page(items, versions)
        items.each do |item|
          catalog_entry = item["catalogEntry"]

          # a package is considered listed if the `listed` property is either `true` or missing
          listed_property = catalog_entry["listed"]
          is_listed = listed_property.nil? || listed_property == true
          if is_listed
            vers = catalog_entry["version"]
            versions << vers
          end
        end
      end

      sig do
        params(repository_details: T::Hash[Symbol, String], dependency_name: String)
          .returns(T.nilable(T::Set[String]))
      end
      private_class_method def self.get_versions_from_search_url_v3(repository_details, dependency_name)
        search_url = repository_details.fetch(:search_url)
        body = execute_json_nuget_request(search_url, repository_details)

        body&.fetch("data")
            &.find { |d| d.fetch("id").casecmp(dependency_name.downcase).zero? }
            &.fetch("versions")
            &.map { |d| d.fetch("version") }
            &.to_set
      end

      sig do
        params(url: String, repository_details: T::Hash[Symbol, T.untyped]).returns(T.nilable(Nokogiri::XML::Document))
      end
      private_class_method def self.execute_xml_nuget_request(url, repository_details)
        response = execute_nuget_request_internal(
          url: url,
          auth_header: repository_details.fetch(:auth_header),
          repository_url: repository_details.fetch(:repository_url)
        )
        return unless response.status == 200

        doc = Nokogiri::XML(response.body)
        doc.remove_namespaces!
        doc
      end

      sig do
        params(url: String,
               repository_details: T::Hash[Symbol, T.untyped])
          .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
      end
      private_class_method def self.execute_json_nuget_request(url, repository_details)
        response = execute_nuget_request_internal(
          url: url,
          auth_header: repository_details.fetch(:auth_header),
          repository_url: repository_details.fetch(:repository_url)
        )
        return unless response.status == 200

        body = HttpResponseHelpers.remove_wrapping_zero_width_chars(response.body)
        JSON.parse(body)
      end

      sig do
        params(url: String, auth_header: T::Hash[Symbol, T.untyped], repository_url: String).returns(Excon::Response)
      end
      private_class_method def self.execute_nuget_request_internal(url:, auth_header:, repository_url:)
        cache = CacheManager.cache("dependency_url_search_cache")
        if cache[url].nil?
          response = Dependabot::RegistryClient.get(
            url: url,
            headers: auth_header
          )

          if [401, 402, 403].include?(response.status)
            raise Dependabot::PrivateSourceAuthenticationFailure, repository_url
          end

          cache[url] = response if !CacheManager.caching_disabled? && response.status == 200
        else
          response = cache[url]
        end

        response
      rescue Excon::Error::Timeout, Excon::Error::Socket
        repo_url = repository_url
        raise if repo_url == Dependabot::Nuget::RepositoryFinder::DEFAULT_REPOSITORY_URL

        raise PrivateSourceTimedOut, repo_url
      end
    end
  end
end
