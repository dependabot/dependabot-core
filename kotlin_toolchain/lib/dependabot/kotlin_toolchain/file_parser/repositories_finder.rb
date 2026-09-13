# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/file_parsers/base"
require "dependabot/kotlin_toolchain/yaml_parser"

module Dependabot
  module KotlinToolchain
    class FileParser < Dependabot::FileParsers::Base
      class RepositoriesFinder
        extend T::Sig

        CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"
        GOOGLE_MAVEN_REPO = "https://maven.google.com"

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, credentials: [])
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(T::Array[String]) }
        def repository_urls
          ([central_repo_url, GOOGLE_MAVEN_REPO] + declared_repository_urls)
            .map { |url| url.sub(%r{/+$}, "") }
            .uniq
        end

        sig { returns(String) }
        def central_repo_url
          base_credential = credentials.find do |credential|
            credential["type"] == "maven_repository" && credential.replaces_base? && credential["url"]
          end

          base_credential ? T.must(base_credential["url"]).sub(%r{/+$}, "") : CENTRAL_REPO_URL
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        def declared_repository_urls
          dependency_files
            .select { |file| file.name.end_with?(".yaml", ".yml") }
            .flat_map { |file| repository_urls_in(parsed_yaml(file)) }
        end

        sig { params(file: Dependabot::DependencyFile).returns(Object) }
        def parsed_yaml(file)
          YamlParser.load(file.content.to_s, filename: file.name)
        end

        sig { params(value: Object).returns(T::Array[String]) }
        def repository_urls_in(value)
          case value
          when Hash
            value.flat_map do |key, nested|
              if key == "repositories" && nested.is_a?(Array)
                repository_entries(nested)
              else
                repository_urls_in(nested)
              end
            end
          when Array
            value.flat_map { |nested| repository_urls_in(nested) }
          else
            []
          end
        end

        sig { params(entries: T::Array[Object]).returns(T::Array[String]) }
        def repository_entries(entries)
          entries.filter_map do |entry|
            url = case entry
                  when String then repository_string(entry)
                  when Hash then entry["url"]
                  end
            url if url.is_a?(String) && valid_url?(url)
          end
        end

        sig { params(value: String).returns(T.nilable(String)) }
        def repository_string(value)
          case value
          when "mavenCentral" then central_repo_url
          when "google" then GOOGLE_MAVEN_REPO
          when "mavenLocal" then nil
          else value
          end
        end

        sig { params(url: String).returns(T::Boolean) }
        def valid_url?(url)
          uri = URI.parse(url)
          %w(http https).include?(uri.scheme) && !uri.host.to_s.empty?
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
