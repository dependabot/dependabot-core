# frozen_string_literal: true

require "excon"
require "python_requirement_parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
        require_relative "pip/requirements_updater"
        require_relative "pip/version"
        require_relative "pip/requirement"

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # pip doesn't (yet) do any dependency resolution. Mad but true.
          # See https://github.com/pypa/pip/issues/988 for details. This should
          # change in pip 10, due in August 2017.
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # Note: when pip has a resolver the logic here will need to change.
          # Currently it gets the latest version that satisfies the existing
          # constraint. In future, it will need to check resolvability, too.
          @latest_resolvable_version_with_no_unlock ||=
            begin
              versions = available_versions
              reqs = dependency.requirements.map do |r|
                Pip::Requirement.new(r.fetch(:requirement).split(","))
              end
              versions.reject!(&:prerelease?) unless wants_prerelease?
              versions.sort.reverse.find do |v|
                reqs.all? { |r| r.satisfied_by?(v) }
              end
            end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        def version_class
          Pip::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for pip because they're not
          # relevant (pip doesn't have a resolver). This method always returns
          # false to ensure `updated_dependencies_after_full_unlock` is never
          # called.
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_version
          versions = available_versions
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.sort.last
        end

        def wants_prerelease?
          if dependency.version
            return Pip::Version.new(dependency.version.tr("+", ".")).prerelease?
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
            index_response = Excon.get(
              Pathname.new(File.join(index_url, normalised_name)).to_s,
              idempotent: true,
              middlewares: SharedHelpers.excon_middleware
            )

            index_response.body.
              scan(%r{<a\s.*?>(.*?)</a>}m).flatten.
              map do |filename|
                version =
                  filename.
                  gsub(/#{name_regex}-/i, "").
                  split(/-|(\.tar\.gz)/).
                  first
                next unless Pip::Version.correct?(version)
                Pip::Version.new(version)
              end.compact
          end
        end

        def index_urls
          main_index_url =
            config_variable_index_urls[:main] ||
            requirement_file_index_urls[:main] ||
            pip_conf_index_urls[:main] ||
            "https://pypi.python.org/simple/"

          extra_index_urls =
            config_variable_index_urls[:extra] +
            requirement_file_index_urls[:extra] +
            pip_conf_index_urls[:extra]

          ([main_index_url] + extra_index_urls).map(&:strip)
        end

        def requirement_file_index_urls
          urls = { main: nil, extra: [] }

          requirements_files.each do |file|
            if file.content.match?(/--index-url\s(.+)/)
              urls[:main] =
                file.content.match(/--index-url\s(.+)/).captures.first
            end
            urls[:extra] += file.content.scan(/--extra-index-url\s(.+)/).flatten
          end

          urls
        end

        def pip_conf_index_urls
          urls = { main: nil, extra: [] }

          return urls unless pip_conf
          content = pip_conf.content

          if content.match?(/index-url\s*=/x)
            urls[:main] = content.match(/index-url\s*=\s*(.+)/).captures.first
          end
          urls[:extra] += content.scan(/extra-index-url\s*=(.+)/).flatten

          urls
        end

        def config_variable_index_urls
          urls = { main: nil, extra: [] }

          index_url_creds = credentials.select { |cred| cred["index-url"] }
          urls[:main] =
            index_url_creds.
            find { |cred| cred["replaces-base"] }&.
            fetch("index-url")
          urls[:extra] =
            index_url_creds.
            reject { |cred| cred["replaces-base"] }.
            map { |cred| cred["index-url"] }

          urls
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.tr("_", "-").tr(".", "-")
        end

        def name_regex
          parts = dependency.name.split(/[\s_-]/).map { |n| Regexp.quote(n) }
          /#{parts.join("[\s_-]")}/i
        end

        def pip_conf
          dependency_files.find { |f| f.name == "pip.conf" }
        end

        def requirements_files
          dependency_files.select { |f| f.name.match?(/requirements/x) }
        end
      end
    end
  end
end
