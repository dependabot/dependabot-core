# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/python/file_parser"
require "dependabot/python/file_updater"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class FileUpdater
      class PipfilePreparer
        extend T::Sig

        sig { params(pipfile_content: String).void }
        def initialize(pipfile_content:)
          @pipfile_content = pipfile_content
        end

        sig { params(credentials: T::Array[T::Hash[String, T.untyped]]).returns(String) }
        def replace_sources(credentials)
          pipfile_object = TomlRB.parse(pipfile_content)

          pipfile_object["source"] =
            pipfile_sources.filter_map { |h| sub_auth_url(h, credentials) } +
            config_variable_sources(credentials)

          TomlRB.dump(pipfile_object)
        end

        sig { params(requirement: String).returns(String) }
        def update_python_requirement(requirement)
          pipfile_object = TomlRB.parse(pipfile_content)

          pipfile_object["requires"] ||= {}
          if pipfile_object.dig("requires", "python_full_version") && pipfile_object.dig("requires", "python_version")
            pipfile_object["requires"].delete("python_full_version")
          elsif pipfile_object.dig("requires", "python_full_version")
            pipfile_object["requires"].delete("python_full_version")
            pipfile_object["requires"]["python_version"] = requirement
          end
          TomlRB.dump(pipfile_object)
        end

        sig { params(parsed_file: String).returns(String) }
        def update_ssl_requirement(parsed_file)
          pipfile_object = TomlRB.parse(pipfile_content)
          parsed_object = TomlRB.parse(parsed_file)

          raise DependencyFileNotResolvable, "Unable to resolve pipfile." unless parsed_object["source"]

          # we parse the verify_ssl value from manifest if it exists
          verify_ssl = parsed_object["source"].map { |x| x["verify_ssl"] }.first

          # provide a default "true" value to file generator in case no value is provided in manifest file
          pipfile_object["source"].each do |key|
            key["verify_ssl"] = verify_ssl.nil? ? true : verify_ssl
          end

          TomlRB.dump(pipfile_object)
        end

        private

        sig { returns(String) }
        attr_reader :pipfile_content

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def pipfile_sources
          @pipfile_sources ||= T.let(TomlRB.parse(pipfile_content).fetch("source", []),
                                     T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end

        sig do
          params(source: T::Hash[String, T.untyped],
                 credentials: T::Array[T::Hash[String, T.untyped]]).returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def sub_auth_url(source, credentials)
          if source["url"].include?("${")
            base_url = source["url"].sub(/\${.*}@/, "")

            source_cred = credentials
                          .select { |cred| cred["type"] == "python_index" && cred["index-url"] }
                          .find { |c| c["index-url"].sub(/\${.*}@/, "") == base_url }

            return nil if source_cred.nil?

            source["url"] = AuthedUrlBuilder.authed_url(credential: source_cred)
          end

          source
        end

        sig { params(credentials: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
        def config_variable_sources(credentials)
          @config_variable_sources = T.let([], T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @config_variable_sources =
            credentials.select { |cred| cred["type"] == "python_index" }.map.with_index do |c, i|
              {
                "name" => "dependabot-inserted-index-#{i}",
                "url" => AuthedUrlBuilder.authed_url(credential: c)
              }
            end
        end
      end
    end
  end
end
