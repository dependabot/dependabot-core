# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/gradle/package/package_details_fetcher"
require "dependabot/kotlin_toolchain/file_parser/repositories_finder"

module Dependabot
  module KotlinToolchain
    module Package
      class PackageDetailsFetcher < Dependabot::Gradle::Package::PackageDetailsFetcher
        extend T::Sig

        sig { override.returns(T::Array[T::Hash[String, Object]]) }
        def dependency_repository_details
          source_urls = dependency.requirements.filter_map do |requirement|
            source = requirement[:source]
            next unless source.is_a?(Hash)

            url = source[:url] || source["url"]
            url if url.is_a?(String)
          end

          urls = FileParser::RepositoriesFinder.new(
            dependency_files: dependency_files,
            credentials: credentials
          ).repository_urls + source_urls

          urls.uniq.map do |url|
            {
              "url" => url.sub(%r{/+$}, ""),
              "auth_headers" => auth_headers(url.sub(%r{/+$}, ""))
            }
          end
        end

        sig { override.returns(T::Array[String]) }
        def group_and_artifact_ids
          name = dependency.metadata[:maven_name]
          name = dependency.name unless name.is_a?(String)
          name.split(":", 2)
        end

        # Google Maven is a default repository for every Kotlin Toolchain
        # project, so it must not take the whole update down when unreachable.
        sig { override.returns(T.nilable(T::Array[T::Hash[Symbol, Object]])) }
        def google_version_details
          super
        rescue Excon::Error::Socket, Excon::Error::Timeout, Excon::Error::TooManyRedirects
          nil
        end

        sig { override.returns(T::Boolean) }
        def plugin?
          false
        end

        sig { override.returns(T::Boolean) }
        def kotlin_plugin?
          false
        end
      end
    end
  end
end
