# frozen_string_literal: true

require "excon"
require "python_requirement_parser"
require "dependabot/update_checkers/base"
require "dependabot/utils/python/requirement"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
        require_relative "pip/requirements_updater"
        require_relative "pip/pipfile_version_resolver"
        require_relative "pip/pip_compile_version_resolver"

        MAIN_PYPI_INDEXES = %w(
          https://pypi.python.org/simple/
          https://pypi.org/simple/
        ).freeze

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            case resolver_type
            when :pipfile
              PipfileVersionResolver.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials,
                unlock_requirement: true,
                latest_allowable_version: latest_version
              ).latest_resolvable_version
            when :pip_compile
              PipCompileVersionResolver.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials,
                unlock_requirement: true,
                latest_allowable_version: latest_version
              ).latest_resolvable_version
            when :requirements
              # pip doesn't (yet) do any dependency resolution, so if we don't
              # have a Pipfile or a pip-compile file, we just return the latest
              # version.
              latest_version
            else raise "Unexpected resolver type #{resolver_type}"
            end
        end

        def latest_resolvable_version_with_no_unlock
          @latest_resolvable_version_with_no_unlock ||=
            case resolver_type
            when :pipfile
              PipfileVersionResolver.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials,
                unlock_requirement: false,
                latest_allowable_version: latest_version
              ).latest_resolvable_version
            when :pip_compile
              PipCompileVersionResolver.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials,
                unlock_requirement: false,
                latest_allowable_version: latest_version
              ).latest_resolvable_version
            when :requirements
              latest_pip_version_with_no_unlock
            else raise "Unexpected resolver type #{resolver_type}"
            end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
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

        def resolver_type
          reqs = dependency.requirements

          if (pipfile && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file) == "Pipfile" }
            return :pipfile
          end

          if (pip_compile_files.any? && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file).end_with?(".in") }
            return :pip_compile
          end

          :requirements
        end

        def fetch_latest_version
          versions = available_versions
          versions.reject! { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.max
        end

        def latest_pip_version_with_no_unlock
          versions = available_versions
          reqs = dependency.requirements.map do |r|
            reqs = (r.fetch(:requirement) || "").split(",").map(&:strip)
            Utils::Python::Requirement.new(reqs)
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

            if index_response.status == 401 || index_response.status == 403
              raise PrivateSourceNotReachable, sanitized_url
            end

            index_response.body.
              scan(%r{<a\s.*?>(.*?)</a>}m).flatten.
              select { |n| n.match?(name_regex) }.
              map do |filename|
                version =
                  filename.
                  gsub(/#{name_regex}-/i, "").
                  split(/-|(\.tar\.gz)/).
                  first
                next unless version_class.correct?(version)
                version_class.new(version)
              end.compact
          rescue Excon::Error::Timeout, Excon::Error::Socket
            next if MAIN_PYPI_INDEXES.include?(index_url)
            raise PrivateSourceNotReachable, sanitized_url
          end
        end

        def index_urls
          main_index_url =
            config_variable_index_urls[:main] ||
            requirement_file_index_urls[:main] ||
            pip_conf_index_urls[:main] ||
            "https://pypi.python.org/simple/"

          if main_index_url
            main_index_url = main_index_url.strip.gsub(%r{/*$}, "") + "/"
          end

          extra_index_urls =
            config_variable_index_urls[:extra] +
            requirement_file_index_urls[:extra] +
            pip_conf_index_urls[:extra]

          extra_index_urls =
            extra_index_urls.map { |url| url.strip.gsub(%r{/*$}, "") + "/" }

          [main_index_url] + extra_index_urls
        end

        def registry_response_for_dependency(index_url)
          Excon.get(
            index_url + normalised_name + "/",
            idempotent: true,
            omit_default_port: true,
            middlewares: SharedHelpers.excon_middleware
          )
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

          index_url_creds = credentials.
                            select { |cred| cred["type"] == "python_index" }
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

        def ignore_reqs
          ignored_versions.
            map { |req| Utils::Python::Requirement.new(req.split(",")) }
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.tr("_", "-").tr(".", "-")
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
