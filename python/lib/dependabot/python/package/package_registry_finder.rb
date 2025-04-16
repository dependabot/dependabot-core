# typed: strict
# frozen_string_literal: true

require "dependabot/python/update_checker"
require "dependabot/python/authed_url_builder"
require "dependabot/errors"

module Dependabot
  module Python
    module Package
      class PackageRegistryFinder
        extend T::Sig
        PYPI_BASE_URL = "https://pypi.org/simple/"
        ENVIRONMENT_VARIABLE_REGEX = /\$\{.+\}/

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Credential],
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency_files:, credentials:, dependency:)
          @dependency_files = dependency_files
          @credentials      = credentials
          @dependency       = dependency
        end

        sig { returns(T::Array[String]) }
        def registry_urls
          extra_index_urls =
            config_variable_index_urls[:extra] +
            pipfile_index_urls[:extra] +
            requirement_file_index_urls[:extra] +
            pip_conf_index_urls[:extra] +
            pyproject_index_urls[:extra]

          extra_index_urls = extra_index_urls.map do |url|
            clean_check_and_remove_environment_variables(url)
          end

          # URL encode any `@` characters within registry URL creds.
          # TODO: The test that fails if the `map` here is removed is likely a
          # bug in Ruby's URI parser, and should be fixed there.
          [main_index_url, *extra_index_urls].map do |url|
            url.rpartition("@").tap { |a| a.first.gsub!("@", "%40") }.join
          end.uniq
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(T::Array[Credential]) }
        attr_reader :credentials

        sig { returns(String) }
        def main_index_url
          url =
            config_variable_index_urls[:main] ||
            pipfile_index_urls[:main] ||
            requirement_file_index_urls[:main] ||
            pip_conf_index_urls[:main] ||
            pyproject_index_urls[:main] ||
            PYPI_BASE_URL

          clean_check_and_remove_environment_variables(url)
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def requirement_file_index_urls # rubocop:disable Metrics/PerceivedComplexity
          urls = T.let({ main: nil, extra: [] }, T::Hash[Symbol, T.untyped])

          requirements_files.each do |file|
            if file.content&.match?(/^--index-url\s+['"]?([^\s'"]+)['"]?/)
              urls[:main] =
                file.content&.match(/^--index-url\s+['"]?([^\s'"]+)['"]?/)
                    &.captures&.first&.strip
            end
            urls[:extra] +=
              file.content
                  &.scan(/^--extra-index-url\s+['"]?([^\s'"]+)['"]?/)
                  &.flatten
                  &.map(&:strip)
          end

          urls
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def pip_conf_index_urls
          urls = T.let({ main: nil, extra: [] }, T::Hash[Symbol, T.untyped])

          return urls unless pip_conf

          content = pip_conf&.content

          if content&.match?(/^index-url\s*=/x)
            urls[:main] = content.match(/^index-url\s*=\s*(.+)/)
                                 &.captures&.first
          end
          urls[:extra] += content&.scan(/^extra-index-url\s*=(.+)/)&.flatten

          urls
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def pipfile_index_urls
          urls = T.let({ main: nil, extra: [] }, T::Hash[Symbol, T.untyped])

          return urls unless pipfile

          pipfile_object = TomlRB.parse(pipfile&.content)

          urls[:main] = pipfile_object["source"]&.first&.fetch("url", nil)

          pipfile_object["source"]&.each do |source|
            urls[:extra] << source.fetch("url") if source["url"]
          end
          urls[:extra] = urls[:extra].uniq

          urls
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          urls || { main: nil, extra: [] }
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def pyproject_index_urls # rubocop:disable Metrics/PerceivedComplexity
          urls = T.let({ main: nil, extra: [] }, T::Hash[Symbol, T.untyped])

          return urls unless pyproject

          sources =
            TomlRB.parse(pyproject&.content).dig("tool", "poetry", "source") ||
            []

          sources.each do |source|
            # If source is PyPI, skip it, and let it pick the default URI
            next if source["name"].casecmp?("PyPI")

            if @dependency.all_sources.include?(source["name"])
              # If dependency has specified this source, use it
              return { main: source["url"], extra: [] }
            elsif source["default"]
              urls[:main] = source["url"]
            elsif source["priority"] != "explicit"
              # if source is not explicit, add it to extra
              urls[:extra] << source["url"]
            end
          end
          urls[:extra] = urls[:extra].uniq

          urls
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          urls || { main: nil, extra: [] }
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def config_variable_index_urls
          urls = T.let({ main: T.let(nil, T.nilable(String)), extra: [] }, T::Hash[Symbol, T.untyped])

          index_url_creds = T.let(
            credentials.select { |cred| cred["type"] == "python_index" }, T::Array[Credential]
          )

          if (main_cred = index_url_creds.find(&:replaces_base?))
            urls[:main] = AuthedUrlBuilder.authed_url(credential: main_cred)
          end

          if index_url_creds.any?
            urls[:extra] =
              index_url_creds
              .reject(&:replaces_base?)
              .map do |cred|
                AuthedUrlBuilder.authed_url(credential: cred)
              end
          end

          urls
        end

        sig { params(url: String).returns(String) }
        def clean_check_and_remove_environment_variables(url)
          url = url.strip.sub(%r{/+$}, "") + "/"

          return authed_base_url(url) unless url.match?(ENVIRONMENT_VARIABLE_REGEX)

          config_variable_urls =
            [
              config_variable_index_urls[:main],
              *config_variable_index_urls[:extra]
            ]
            .compact
            .map { |u| u.strip.gsub(%r{/*$}, "") + "/" }

          regexp = url
                   .sub(%r{(?<=://).+@}, "")
                   .sub(%r{https?://}, "")
                   .split(ENVIRONMENT_VARIABLE_REGEX)
                   .map { |part| Regexp.quote(part) }
                   .join(".+")
          authed_url = config_variable_urls.find { |u| u.match?(regexp) }
          return authed_url if authed_url

          cleaned_url = url.gsub(%r{#{ENVIRONMENT_VARIABLE_REGEX}/?}o, "")
          authed_url = authed_base_url(cleaned_url)
          return authed_url if credential_for(cleaned_url)

          raise PrivateSourceAuthenticationFailure, url
        end

        sig { params(base_url: String).returns(String) }
        def authed_base_url(base_url)
          cred = credential_for(base_url)
          return base_url unless cred

          T.must(AuthedUrlBuilder.authed_url(credential: cred)).gsub(%r{/*$}, "") + "/"
        end

        sig { params(url: String).returns(T.nilable(Credential)) }
        def credential_for(url)
          credentials
            .select { |c| c["type"] == "python_index" }
            .find do |c|
              cred_url = c.fetch("index-url").gsub(%r{/*$}, "") + "/"
              cred_url.include?(url)
            end
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pip_conf
          dependency_files.find { |f| f.name == "pip.conf" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def requirements_files
          dependency_files.select { |f| f.name.match?(/requirements/x) }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end
      end
    end
  end
end
