# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/sbt/file_parser"

module Dependabot
  module Sbt
    class FileParser < Dependabot::FileParsers::Base
      class RepositoriesFinder
        extend T::Sig

        CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"

        # Matches: resolvers += "Name" at "https://url"
        RESOLVER_AT_REGEX = T.let(
          /resolvers\s*\+?=\s*(?:Seq\s*\()?\s*"[^"]*"\s+at\s+"(?<url>[^"]+)"/,
          Regexp
        )

        # Matches: resolvers ++= Seq("Name" at "url", ...)
        RESOLVER_SEQ_AT_REGEX = T.let(
          /"[^"]*"\s+at\s+"(?<url>[^"]+)"/,
          Regexp
        )

        # Matches: Resolver.url("name", url("https://url"))
        RESOLVER_URL_REGEX = T.let(
          /Resolver\.url\(\s*"[^"]*"\s*,\s*url\(\s*"(?<url>[^"]+)"\s*\)/,
          Regexp
        )

        # Matches: MavenRepository("name", "https://url")
        MAVEN_REPOSITORY_REGEX = T.let(
          /MavenRepository\(\s*"[^"]*"\s*,\s*"(?<url>[^"]+)"\s*\)/,
          Regexp
        )

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, credentials: [])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
        end

        sig { returns(T::Array[String]) }
        def repository_urls
          urls = T.let([], T::Array[String])

          sbt_files.each do |file|
            urls += repository_urls_from(file)
          end

          # SBT always includes Maven Central as a default resolver.
          # Custom resolvers supplement but don't replace it.
          urls << central_repo_url unless urls.include?(central_repo_url)

          urls.uniq
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { params(buildfile: Dependabot::DependencyFile).returns(T::Array[String]) }
        def repository_urls_from(buildfile)
          content = comment_free_content(buildfile)

          urls = [RESOLVER_AT_REGEX, RESOLVER_SEQ_AT_REGEX, RESOLVER_URL_REGEX, MAVEN_REPOSITORY_REGEX]
                 .flat_map { |regex| scan_urls(content, regex) }

          urls
            .map { |url| url.strip.gsub(%r{/$}, "") }
            .select { |url| valid_url?(url) }
            .uniq
        end

        sig { params(content: String, regex: Regexp).returns(T::Array[String]) }
        def scan_urls(content, regex)
          urls = T.let([], T::Array[String])
          content.scan(regex) do
            urls << T.must(T.must(Regexp.last_match).named_captures.fetch("url"))
          end
          urls
        end

        sig { returns(String) }
        def central_repo_url
          base_credential = credentials.find do |cred|
            cred["type"] == "maven_repository" && replaces_base?(cred) && cred["url"]
          end

          base_credential ? T.must(base_credential["url"]).gsub(%r{/+$}, "") : CENTRAL_REPO_URL
        end

        sig { params(credential: Dependabot::Credential).returns(T::Boolean) }
        def replaces_base?(credential)
          if credential.respond_to?(:replaces_base?)
            credential.replaces_base?
          else
            credential["replaces-base"] == true
          end
        end

        sig { params(url: String).returns(T::Boolean) }
        def valid_url?(url)
          return false unless url.start_with?("http")

          URI.parse(url)
          true
        rescue URI::InvalidURIError
          false
        end

        sig { params(buildfile: Dependabot::DependencyFile).returns(String) }
        def comment_free_content(buildfile)
          T.must(buildfile.content)
           .gsub(%r{(?<=^|\s)//.*$}, "\n")
           .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def sbt_files
          @sbt_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?(".sbt") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end
      end
    end
  end
end
