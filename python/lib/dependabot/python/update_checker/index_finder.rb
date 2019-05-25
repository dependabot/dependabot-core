# frozen_string_literal: true

require "dependabot/python/update_checker"
require "dependabot/python/authed_url_builder"
require "dependabot/errors"

module Dependabot
  module Python
    class UpdateChecker
      class IndexFinder
        PYPI_BASE_URL = "https://pypi.python.org/simple/"
        ENVIRONMENT_VARIABLE_REGEX = /\$\{.+\}/.freeze

        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials      = credentials
        end

        def index_urls
          extra_index_urls =
            config_variable_index_urls[:extra] +
            pipfile_index_urls[:extra] +
            requirement_file_index_urls[:extra] +
            pip_conf_index_urls[:extra]

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

        attr_reader :dependency_files, :credentials

        def main_index_url
          url =
            config_variable_index_urls[:main] ||
            pipfile_index_urls[:main] ||
            requirement_file_index_urls[:main] ||
            pip_conf_index_urls[:main] ||
            PYPI_BASE_URL

          return unless url

          clean_check_and_remove_environment_variables(url)
        end

        def requirement_file_index_urls
          urls = { main: nil, extra: [] }

          requirements_files.each do |file|
            if file.content.match?(/^--index-url\s([^\s]+)/)
              urls[:main] =
                file.content.match(/^--index-url\s([^\s]+)/).captures.first
            end
            urls[:extra] += file.content.scan(/^--extra-index-url\s([^\s]+)/).
                            flatten
          end

          urls
        end

        def pip_conf_index_urls
          urls = { main: nil, extra: [] }

          return urls unless pip_conf

          content = pip_conf.content

          if content.match?(/^index-url\s*=/x)
            urls[:main] = content.match(/^index-url\s*=\s*(.+)/).
                          captures.first
          end
          urls[:extra] += content.scan(/^extra-index-url\s*=(.+)/).flatten

          urls
        end

        def pipfile_index_urls
          urls = { main: nil, extra: [] }

          return urls unless pipfile

          pipfile_object = TomlRB.parse(pipfile.content)

          urls[:main] = pipfile_object["source"]&.first&.fetch("url", nil)

          pipfile_object["source"]&.each do |source|
            urls[:extra] << source.fetch("url") if source["url"]
          end
          urls[:extra] = urls[:extra].uniq

          urls
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          urls
        end

        def config_variable_index_urls
          urls = { main: nil, extra: [] }

          index_url_creds = credentials.
                            select { |cred| cred["type"] == "python_index" }

          if (main_cred = index_url_creds.find { |cred| cred["replaces-base"] })
            urls[:main] = AuthedUrlBuilder.authed_url(credential: main_cred)
          end

          urls[:extra] =
            index_url_creds.
            reject { |cred| cred["replaces-base"] }.
            map { |cred| AuthedUrlBuilder.authed_url(credential: cred) }

          urls
        end

        def clean_check_and_remove_environment_variables(url)
          url = url.strip.gsub(%r{/*$}, "") + "/"

          unless url.match?(ENVIRONMENT_VARIABLE_REGEX)
            return authed_base_url(url)
          end

          config_variable_urls =
            [
              config_variable_index_urls[:main],
              *config_variable_index_urls[:extra]
            ].
            compact.
            map { |u| u.strip.gsub(%r{/*$}, "") + "/" }

          regexp = url.split(ENVIRONMENT_VARIABLE_REGEX).
                   map { |part| Regexp.quote(part) }.
                   join(".+")
          authed_url = config_variable_urls.find { |u| u.match?(regexp) }
          return authed_url if authed_url

          cleaned_url = url.gsub(%r{#{ENVIRONMENT_VARIABLE_REGEX}/?}, "")
          authed_url = authed_base_url(cleaned_url)
          return authed_url if credential_for(cleaned_url)

          raise PrivateSourceAuthenticationFailure, url
        end

        def authed_base_url(base_url)
          cred = credential_for(base_url)
          return base_url unless cred

          AuthedUrlBuilder.authed_url(credential: cred).gsub(%r{/*$}, "") + "/"
        end

        def credential_for(url)
          credentials.
            select { |c| c["type"] == "python_index" }.
            find do |c|
              cred_url = c.fetch("index-url").gsub(%r{/*$}, "") + "/"
              cred_url.include?(url)
            end
        end

        def pip_conf
          dependency_files.find { |f| f.name == "pip.conf" }
        end

        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def requirements_files
          dependency_files.select { |f| f.name.match?(/requirements/x) }
        end

        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end
      end
    end
  end
end
