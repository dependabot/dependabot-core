# frozen_string_literal: true

require "excon"

require "dependabot/python/update_checker"
require "dependabot/shared_helpers"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder
        ENVIRONMENT_VARIABLE_REGEX = /\$\{.+\}/.freeze

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_version_with_no_unlock
          @latest_version_with_no_unlock ||=
            fetch_latest_version_with_no_unlock
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions

        def fetch_latest_version
          versions = available_versions
          versions.reject! { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.max
        end

        def fetch_latest_version_with_no_unlock
          versions = available_versions
          reqs = dependency.requirements.map do |r|
            reqs = (r.fetch(:requirement) || "").split(",").map(&:strip)
            requirement_class.new(reqs)
          end
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.sort.reverse.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }.
            find { |v| reqs.all? { |r| r.satisfied_by?(v) } }
        end

        def wants_prerelease?
          if dependency.version
            version = version_class.new(dependency.version.tr("+", "."))
            return version.prerelease?
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        # See https://www.python.org/dev/peps/pep-0503/ for details of the
        # Simple Repository API we use here.
        def available_versions
          index_urls.flat_map do |index_url|
            sanitized_url = index_url.gsub(%r{(?<=//).*(?=@)}, "redacted")
            index_response = registry_response_for_dependency(index_url)

            if [401, 403].include?(index_response.status) &&
               [401, 403].include?(registry_index_response(index_url).status)
              raise PrivateSourceAuthenticationFailure, sanitized_url
            end

            index_response.body.
              scan(%r{<a\s.*?>(.*?)</a>}m).flatten.
              select { |n| n.match?(name_regex) }.
              map do |filename|
                version =
                  filename.
                  gsub(/#{name_regex}-/i, "").
                  split(/-|\.tar\.|\.zip|\.whl/).
                  first
                next unless version_class.correct?(version)

                version_class.new(version)
              end.compact
          rescue Excon::Error::Timeout, Excon::Error::Socket
            next if MAIN_PYPI_INDEXES.include?(index_url)

            raise PrivateSourceAuthenticationFailure, sanitized_url
          end
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

          [main_index_url, *extra_index_urls].uniq
        end

        def main_index_url
          url =
            config_variable_index_urls[:main] ||
            pipfile_index_urls[:main] ||
            requirement_file_index_urls[:main] ||
            pip_conf_index_urls[:main] ||
            "https://pypi.python.org/simple/"

          return unless url

          clean_check_and_remove_environment_variables(url)
        end

        def registry_response_for_dependency(index_url)
          Excon.get(
            index_url + normalised_name + "/",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
        end

        def registry_index_response(index_url)
          Excon.get(
            index_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
        end

        def requirement_file_index_urls
          urls = { main: nil, extra: [] }

          requirements_files.each do |file|
            if file.content.match?(/^--index-url\s(.+)/)
              urls[:main] =
                file.content.match(/^--index-url\s(.+)/).captures.first
            end
            urls[:extra] += file.content.scan(/^--extra-index-url\s(.+)/).
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

        # Has test that it works without username / password.
        # TODO: Test with proxy
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
          url = url.gsub(%r{#{ENVIRONMENT_VARIABLE_REGEX}/?}, "")
          authed_base_url(url)
        end

        def authed_base_url(base_url)
          cred = credentials.
                  select { |c| c["type"] == "python_index" }.
                  find { |c| c.fetch("index-url").include?(base_url) }
          return base_url unless cred

          AuthedUrlBuilder.authed_url(credential: cred)
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.gsub(/[-_.]+/, "-")
        end

        def name_regex
          parts = dependency.name.split(/[\s_.-]/).map { |n| Regexp.quote(n) }
          /#{parts.join("[\s_.-]")}/i
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

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end
      end
    end
  end
end
