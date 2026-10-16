# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"
require "dependabot/python/update_checker"
require "dependabot/python/authed_url_builder"
require "dependabot/errors"

module Dependabot
  module Python
    module Package
      class PackageRegistryFinder
        extend T::Sig

        PYPI_BASE_URL = "https://pypi.org/simple/"
        PUBLIC_PYPI_HOSTS = %w(
          pypi.org
          pypi.python.org
        ).freeze
        PUBLIC_PYPI_PATH = "/simple"
        ENVIRONMENT_VARIABLE_REGEX = /\$\{.+\}/

        UrlsHash = T.type_alias { { main: T.nilable(String), extra: T::Array[String] } }

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
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

          # URL encode any `@` characters within registry URL creds. This is done
          # before the URLs are classified and ordered below, so that a URL with
          # unescaped credentials is still parseable.
          # TODO: The test that fails if the `map` here is removed is likely a
          # bug in Ruby's URI parser, and should be fixed there.
          extra_index_urls = extra_index_urls.map do |url|
            escape_userinfo(clean_check_and_remove_environment_variables(url))
          end

          # A `replaces-base` registry, or public PyPI when no index is
          # configured, is searched last so that fully private registries take
          # precedence, avoiding dependency confusion attacks where a private
          # package name is claimed by a public package of the same name.
          #
          # An index explicitly configured in a dependency file (a
          # `--index-url`, a `pip.conf` `index-url`, or a default Poetry source)
          # is an intentional choice of primary registry, so it keeps its place
          # ahead of the extra indexes.
          #
          # The main index is removed from the extras first, so that declaring it
          # as both a main and an extra index (as a Pipfile `[[source]]` does)
          # doesn't keep it at the front of the list.
          main_url = escape_userinfo(main_index_url)
          other_urls = extra_index_urls.reject { |url| url == main_url }

          ordered_urls =
            if demote_main_index?(main_url)
              other_urls + [main_url]
            else
              [main_url] + other_urls
            end

          # A configured main index may itself be fully private, while an extra
          # index may be public PyPI, so the public indexes are always moved to
          # the back rather than assuming the main index is the public one.
          private_urls, public_urls = ordered_urls.uniq.partition do |url|
            !public_pypi_url?(url)
          end

          private_urls + public_urls
        end

        private

        # The main index is only demoted below the extra indexes when it isn't a
        # deliberate choice of primary private registry: either it comes from a
        # `replaces-base` credential, or it's public PyPI.
        sig { params(main_url: String).returns(T::Boolean) }
        def demote_main_index?(main_url)
          return true if public_pypi_url?(main_url)

          !config_variable_index_urls[:main].nil?
        end

        sig { params(url: String).returns(String) }
        def escape_userinfo(url)
          url.rpartition("@").tap { |a| a.first.gsub!("@", "%40") }.join
        end

        # Identifies the public PyPI index by its parsed host, scheme, port and
        # path, so that equivalent spellings (case differences, an explicit
        # default port, credentials, trailing slashes) aren't mistaken for a
        # private index.
        sig { params(url: String).returns(T::Boolean) }
        def public_pypi_url?(url)
          uri = URI.parse(url)
          return false unless uri.is_a?(URI::HTTP)

          host = uri.host&.downcase
          return false unless host && PUBLIC_PYPI_HOSTS.include?(host)
          return false unless uri.port == uri.default_port

          uri.path.to_s.chomp("/") == PUBLIC_PYPI_PATH
        rescue URI::InvalidURIError
          false
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
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

        sig { returns(UrlsHash) }
        def requirement_file_index_urls
          urls = T.let({ main: nil, extra: [] }, UrlsHash)

          requirements_files.each do |file|
            content = T.must(file.content)
            if content.match?(/^--index-url\s+['"]?([^\s'"]+)['"]?/)
              urls[:main] =
                T.must(content.match(/^--index-url\s+['"]?([^\s'"]+)['"]?/))
                 .captures.first&.strip
            end
            extra_urls = urls[:extra]
            extra_urls +=
              content
              .scan(/^--extra-index-url\s+['"]?([^\s'"]+)['"]?/)
              .flatten
              .map(&:strip)
            urls[:extra] = extra_urls
          end

          urls
        end

        sig { returns(UrlsHash) }
        def pip_conf_index_urls
          urls = T.let({ main: nil, extra: [] }, UrlsHash)

          return urls unless pip_conf

          content = T.must(pip_conf).content
          return urls unless content

          if content.match?(/^index-url\s*=/x)
            urls[:main] = T.must(content.match(/^index-url\s*=\s*(.+)/))
                           .captures.first
          end
          extra_urls = urls[:extra]
          extra_urls += content.scan(/^extra-index-url\s*=(.+)/).flatten
          urls[:extra] = extra_urls

          urls
        end

        sig { returns(UrlsHash) }
        def pipfile_index_urls
          urls = T.let({ main: nil, extra: [] }, UrlsHash)
          begin
            return urls unless pipfile

            content = T.must(pipfile).content
            return urls unless content

            pipfile_object = TomlRB.parse(content)

            urls[:main] = pipfile_object["source"]&.first&.fetch("url", nil)

            pipfile_object["source"]&.each do |source|
              urls[:extra] << source.fetch("url") if source["url"]
            end
            urls[:extra] = urls[:extra].uniq

            urls
          rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
            urls
          end
        end

        sig { returns(UrlsHash) }
        def pyproject_index_urls
          urls = T.let({ main: nil, extra: [] }, UrlsHash)

          begin
            return urls unless pyproject

            sources =
              TomlRB.parse(T.must(T.must(pyproject).content)).dig("tool", "poetry", "source") ||
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
            urls
          end
        end

        sig { returns(UrlsHash) }
        def config_variable_index_urls
          urls = T.let({ main: nil, extra: [] }, UrlsHash)

          index_url_creds = credentials
                            .select { |cred| cred["type"] == "python_index" }

          if (main_cred = index_url_creds.find(&:replaces_base?))
            urls[:main] = AuthedUrlBuilder.authed_url(credential: main_cred)
          end

          urls[:extra] =
            index_url_creds
            .reject(&:replaces_base?)
            .map { |cred| AuthedUrlBuilder.authed_url(credential: cred) }

          urls
        end

        sig { params(url: String).returns(String) }
        def clean_check_and_remove_environment_variables(url)
          url = with_single_trailing_slash(url.strip)

          return authed_base_url(url) unless url.match?(ENVIRONMENT_VARIABLE_REGEX)

          config_variable_urls =
            [
              config_variable_index_urls[:main],
              *config_variable_index_urls[:extra]
            ]
            .compact
            .map { |u| with_single_trailing_slash(u.strip) }

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

          with_single_trailing_slash(AuthedUrlBuilder.authed_url(credential: cred))
        end

        sig { params(url: String).returns(T.nilable(Dependabot::Credential)) }
        def credential_for(url)
          credentials
            .select { |c| c["type"] == "python_index" }
            .find do |c|
              cred_url = with_single_trailing_slash(c.fetch("index-url"))
              cred_url.include?(url)
            end
        end

        sig { params(url: String).returns(String) }
        def with_single_trailing_slash(url)
          normalized_url = url.dup
          normalized_url.chop! while normalized_url.end_with?("/")
          normalized_url + "/"
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
