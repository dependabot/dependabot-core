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
                  gsub(/#{Regexp.quote(normalised_name)}-/i, "").
                  gsub(/#{Regexp.quote(dependency.name)}-/i, "").
                  split(/-|(\.tar\.gz)/).
                  first
                begin
                  Pip::Version.new(version)
                rescue ArgumentError
                  nil
                end
              end.compact
          end
        end

        def index_urls
          main_index_url = "https://pypi.python.org/simple/"
          extra_index_urls = []

          requirements_files.each do |file|
            if file.content.match?(/--index-url\s(.+)/)
              main_index_url =
                file.content.match(/--index-url\s(.+)/).captures.first
            end
            extra_index_urls +=
              file.content.scan(/--extra-index-url\s(.+)/).flatten
          end

          if pip_conf
            if pip_conf.content.match?(/index-url\s*=/x)
              main_index_url =
                pip_conf.content.match(/index-url\s*=\s*(.+)/).captures.first
            end
            extra_index_urls +=
              pip_conf.content.scan(/extra-index-url\s*=(.+)/).flatten
          end

          index_urls = [main_index_url] + extra_index_urls
          index_urls.map(&:strip)
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.tr("_", "-").tr(".", "-")
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
