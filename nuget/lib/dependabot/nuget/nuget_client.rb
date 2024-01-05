# typed: true
# frozen_string_literal: true

require "dependabot/nuget/cache_manager"
require "dependabot/nuget/update_checker/repository_finder"

module Dependabot
  module Nuget
    class NugetClient
      def self.get_package_versions_v3(dependency_name, repository_details)
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

      private_class_method def self.get_versions_from_versions_url_v3(repository_details)
        body = execute_search_for_dependency_url(repository_details[:versions_url], repository_details)
        body&.fetch("versions")
      end

      private_class_method def self.get_versions_from_registration_v3(repository_details)
        url = repository_details[:registration_url]
        body = execute_search_for_dependency_url(url, repository_details)
        if body
          pages = body.fetch("items")
          versions = Set.new
          pages.each do |page|
            items = page["items"]
            if items
              # inlined entries
              items.each do |item|
                catalog_entry = item["catalogEntry"]
                if catalog_entry["listed"] == true
                  vers = catalog_entry["version"]
                  versions << vers
                end
              end
            else
              # paged entries
              page_url = page["@id"]
              page_body = execute_search_for_dependency_url(page_url, repository_details)
              items = page_body.fetch("items")
              items.each do |item|
                catalog_entry = item.fetch("catalogEntry")
                versions << catalog_entry.fetch("version") if catalog_entry["listed"] == true
              end
            end
          end

          versions
        else
          nil
        end
      end

      private_class_method def self.get_versions_from_search_url_v3(repository_details, dependency_name)
        search_url = repository_details[:search_url]
        body = execute_search_for_dependency_url(search_url, repository_details)

        body&.fetch("data")
            &.find { |d| d.fetch("id").casecmp(dependency_name.downcase).zero? }
            &.fetch("versions")
            &.map { |d| d.fetch("version") }
      end

      private_class_method def self.execute_search_for_dependency_url(url, repository_details)
        cache = CacheManager.cache("dependency_url_search_cache")
        cache[url] ||= Dependabot::RegistryClient.get(
          url: url,
          headers: repository_details[:auth_header]
        )

        response = cache[url]

        return unless response.status == 200

        body = remove_wrapping_zero_width_chars(response.body)
        JSON.parse(body)
      rescue Excon::Error::Timeout, Excon::Error::Socket
        repo_url = repository_details[:repository_url]
        raise if repo_url == Dependabot::Nuget::UpdateChecker::RepositoryFinder::DEFAULT_REPOSITORY_URL

        raise PrivateSourceTimedOut, repo_url
      end

      private_class_method def self.remove_wrapping_zero_width_chars(string)
        string.force_encoding("UTF-8").encode
              .gsub(/\A[\u200B-\u200D\uFEFF]/, "")
              .gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
      end
    end
  end
end
