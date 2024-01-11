# typed: true
# frozen_string_literal: true

require "dependabot/errors"
require "dependabot/nuget/cache_manager"
require "dependabot/nuget/update_checker/repository_finder"

module Dependabot
  module Nuget
    class NugetClient
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

      def self.get_packages(repository_details)
        repository_type = repository_details.fetch(:repository_type)
        return get_packages_from_registration_v3(repository_details) if repository_type == "v3"

        raise "Unknown repotype #{repository_type}"
      end

      def self.build_repository_details(repo_details, dependency_name)
        response = get_repo_metadata_response(repo_details)
        return unless response.status == 200

        body = remove_wrapping_zero_width_chars(response.body)
        parsed_json = JSON.parse(body)

        base_url = base_url_from_v3_metadata(parsed_json)
        resolved_base_url = base_url || repo_details.fetch(:url).gsub("/index.json", "-flatcontainer")
        search_url = search_url_from_v3_metadata(parsed_json)
        registration_url = registration_url_from_v3_metadata(parsed_json)

        details = {
          base_url: resolved_base_url,
          repository_url: repo_details.fetch(:url),
          auth_header: auth_header_for_token(repo_details.fetch(:token)),
          repository_type: "v3"
        }
        if base_url
          details[:versions_url] =
            File.join(base_url, dependency_name.downcase, "index.json")
        end
        if search_url
          details[:search_url] =
            search_url + "?q=#{dependency_name.downcase}&prerelease=true&semVerLevel=2.0.0"
        end

        if registration_url
          details[:registration_url] = File.join(registration_url, dependency_name.downcase, "index.json")
        end

        details
      rescue JSON::ParserError
        build_v2_url(response, repo_details, dependency_name)
      end

      private_class_method def self.get_package_versions_v2(dependency_name, repository_details)
        doc = execute_xml_nuget_request(repository_details.fetch(:versions_url), repository_details)
        return unless doc

        id_nodes = doc.xpath("/feed/entry/properties/Id")
        matching_versions = Set.new
        id_nodes.each do |id_node|
          return nil unless id_node.text

          next unless id_node.text.casecmp?(dependency_name)

          version_node = id_node.parent.xpath("Version")
          matching_versions << version_node.text if version_node && version_node.text
        end

        matching_versions
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
        end
      end

      private_class_method def self.registration_url_from_v3_metadata(metadata)
        allowed_registration_types = %w(
          RegistrationsBaseUrl
          RegistrationsBaseUrl/3.0.0-beta
          RegistrationsBaseUrl/3.0.0-rc
          RegistrationsBaseUrl/3.4.0
          RegistrationsBaseUrl/3.6.0
        )
        metadata
          .fetch("resources", [])
          .find { |r| allowed_registration_types.find { |s| r.fetch("@type") == s } }
          &.fetch("@id")
      end

      private_class_method def self.search_url_from_v3_metadata(metadata)
        # allowable values from here: https://learn.microsoft.com/en-us/nuget/api/search-query-service-resource#versioning
        allowed_search_types = %w(
          SearchQueryService
          SearchQueryService/3.0.0-beta
          SearchQueryService/3.0.0-rc
          SearchQueryService/3.5.0
        )
        metadata
          .fetch("resources", [])
          .find { |r| allowed_search_types.find { |s| r.fetch("@type") == s } }
          &.fetch("@id")
      end

      private_class_method def self.base_url_from_v3_metadata(metadata)
        metadata
          .fetch("resources", [])
          .find { |r| r.fetch("@type") == "PackageBaseAddress/3.0.0" }
          &.fetch("@id")
      end

      private_class_method def self.build_v2_url(response, repo_details, dependency_name)
        doc = Nokogiri::XML(response.body)

        doc.remove_namespaces!
        base_url = doc.at_xpath("service")&.attributes
                      &.fetch("base", nil)&.value

        base_url ||= repo_details.fetch(:url)

        {
          base_url: base_url,
          repository_url: base_url,
          versions_url: File.join(
            base_url,
            "FindPackagesById()?id='#{dependency_name}'"
          ),
          auth_header: auth_header_for_token(repo_details.fetch(:token)),
          repository_type: "v2"
        }
      end

      private_class_method def self.auth_header_for_token(token)
        return {} unless token

        if token.include?(":")
          encoded_token = Base64.strict_encode64(token).delete("\n").chomp
          { "Authorization" => "Basic #{encoded_token}" }
        elsif Base64.decode64(token).ascii_only? &&
              Base64.decode64(token).include?(":")
          { "Authorization" => "Basic #{token.delete("\n")}" }
        else
          { "Authorization" => "Bearer #{token}" }
        end
      end

      private_class_method def self.get_repo_metadata_response(repository_details)
        auth_header = auth_header_for_token(repository_details.fetch(:token))

        execute_nuget_request_internal(
          url: repository_details[:url],
          auth_header: auth_header,
          repository_url: repository_details[:url]
        )
      end

      private_class_method def self.get_versions_from_versions_url_v3(repository_details)
        body = execute_json_nuget_request(repository_details[:versions_url], repository_details)
        body&.fetch("versions")
      end

      private_class_method def self.get_versions_from_registration_v3(repository_details)
        versions = Set.new
        packages = get_packages_from_registration_v3(repository_details)
        return unless packages

        packages.each do |package|
          versions << package["version"]
        end
        versions
      end

      private_class_method def self.get_packages_from_registration_v3(repository_details)
        url = repository_details[:registration_url]
        body = execute_json_nuget_request(url, repository_details)
        return unless body

        packages = []
        pages = body.fetch("items")
        pages.each do |page|
          items = page["items"]
          if items
            # inlined entries
            items.each do |item|
              catalog_entry = item["catalogEntry"]
              packages << catalog_entry if catalog_entry["listed"] == true
            end
          else
            # paged entries
            page_url = page["@id"]
            page_body = execute_json_nuget_request(page_url, repository_details)
            items = page_body.fetch("items")
            items.each do |item|
              catalog_entry = item.fetch("catalogEntry")
              packages << catalog_entry if catalog_entry["listed"] == true
            end
          end
        end

        packages
      end

      private_class_method def self.get_versions_from_search_url_v3(repository_details, dependency_name)
        search_url = repository_details[:search_url]
        body = execute_json_nuget_request(search_url, repository_details)

        body&.fetch("data")
            &.find { |d| d.fetch("id").casecmp(dependency_name.downcase).zero? }
            &.fetch("versions")
            &.map { |d| d.fetch("version") }
      end

      private_class_method def self.execute_xml_nuget_request(url, repository_details)
        response = execute_nuget_request_internal(
          url: url,
          auth_header: repository_details[:auth_header],
          repository_url: repository_details[:repository_url]
        )
        return unless response.status == 200

        doc = Nokogiri::XML(response.body)
        doc.remove_namespaces!
        doc
      end

      private_class_method def self.execute_json_nuget_request(url, repository_details)
        response = execute_nuget_request_internal(
          url: url,
          auth_header: repository_details[:auth_header],
          repository_url: repository_details[:repository_url]
        )
        return unless response.status == 200

        body = remove_wrapping_zero_width_chars(response.body)
        JSON.parse(body)
      end

      private_class_method def self.execute_nuget_request_internal(
        url: String,
        auth_header: String,
        repository_url: String
      )
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
        raise if repo_url == Dependabot::Nuget::UpdateChecker::RepositoryFinder::DEFAULT_REPOSITORY_URL

        raise PrivateSourceTimedOut, repo_url
      end

      private_class_method def self.remove_wrapping_zero_width_chars(string)
        return string if string.frozen?

        string.force_encoding("UTF-8").encode
              .gsub(/\A[\u200B-\u200D\uFEFF]/, "")
              .gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
      end
    end
  end
end
