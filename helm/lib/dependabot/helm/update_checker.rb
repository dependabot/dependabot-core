# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/docker/version"
require "dependabot/docker/requirement"
require "dependabot/shared/utils/credentials_finder"
require "excon"
require "yaml"

module Dependabot
  module Helm
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(T.any(String, Gem::Version)))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        dependency.version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.map do |req|
          updated_metadata = req.fetch(:metadata).dup
          updated_req = req.dup
          if updated_metadata.key?(:type) && updated_metadata[:type] == :helm_chart
            updated_req[:requirement] = latest_version.to_s
            updated_req[:source][:tag] = latest_version.to_s
          end

          updated_req
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def version_can_update?(requirements_to_unlock:) # rubocop:disable Lint/UnusedMethodArgument
        return false unless latest_version

        version_class.new(latest_version.to_s) > version_class.new(dependency.version)
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version
        case dependency_type
        when :chart_dependency
          fetch_latest_chart_version
        when :image_reference
          fetch_latest_image_version
        else
          Gem::Version.new(dependency.version)
        end
      end

      sig { returns(Symbol) }
      def dependency_type
        req = dependency.requirements.first

        return :image_reference if T.must(req)[:groups]&.include?("image")
        return :chart_dependency if T.must(req).dig(:metadata, :type) == :helm_chart

        :unknown
      end

      sig { params(index_url: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def fetch_helm_chart_index(index_url)
        Dependabot.logger.info("Fetching Helm chart index from #{index_url}")

        response = Excon.get(
          index_url,
          idempotent: true,
          middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
        )

        Dependabot.logger.info("Received response from #{index_url} with status #{response.status}")

        YAML.safe_load(response.body)
      rescue Excon::Error => e
        Dependabot.logger.error("Error fetching Helm index from #{index_url}: #{e.message}")
        nil
      rescue StandardError => e
        Dependabot.logger.error("Error parsing Helm index: #{e.message}")
        nil
      end

      sig { params(all_versions: T::Array[String]).returns(T::Array[String]) }
      def filter_valid_versions(all_versions)
        all_versions.reject do |version|
          version_class.new(version) <= version_class.new(dependency.version) ||
            ignore_requirements.any? { |r| r.satisfied_by?(version_class.new(version)) }
        end
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_chart_version
        source_url = dependency.requirements.first&.dig(:source, :registry)
        return nil unless source_url

        repo_url = source_url.to_s.strip.chomp("/")
        chart_name = dependency.name
        index_url = "#{repo_url}/index.yaml"

        index = fetch_helm_chart_index(index_url)
        return nil unless index && index["entries"] && index["entries"][chart_name]

        all_versions = index["entries"][chart_name].map { |entry| entry["version"] }
        Dependabot.logger.info("Found #{all_versions.length} versions for #{chart_name}")

        valid_versions = filter_valid_versions(all_versions)
        Dependabot.logger.info("After filtering, found #{valid_versions.length} valid versions for #{chart_name}")

        return nil if valid_versions.empty?

        highest_version = valid_versions.map { |v| version_class.new(v) }.max
        Dependabot.logger.info("Highest valid version for #{chart_name} is #{highest_version}")

        highest_version
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_image_version
        docker_dependency = build_docker_dependency

        Dependabot.logger.info("Delegating to Docker UpdateChecker for image: #{docker_dependency.name}")

        docker_checker = Dependabot::UpdateCheckers.for_package_manager("docker").new(
          dependency: docker_dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories,
          raise_on_ignored: raise_on_ignored
        )

        latest = docker_checker.latest_version
        latest_version_str = latest&.to_s

        Dependabot.logger.info("Docker UpdateChecker found latest version: #{latest_version_str || 'none'}")

        latest_version_str
      end

      sig { returns(Dependabot::Dependency) }
      def build_docker_dependency
        source = T.must(dependency.requirements.first)[:source]
        name = dependency.name
        version = dependency.version

        if source[:path]
          parts = source[:path].split(".")
          if parts.length > 1 && (parts.last == "tag" || parts.last == "image")
            # The actual image name might be in image.repository
            name = parts[0...-1].join(".")
          end
        end

        registry = source[:registry] || "docker.io"

        Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            file: T.must(dependency.requirements.first)[:file],
            source: {
              registry: registry,
              tag: version
            }
          }],
          package_manager: "helm"
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("helm", Dependabot::Helm::UpdateChecker)
