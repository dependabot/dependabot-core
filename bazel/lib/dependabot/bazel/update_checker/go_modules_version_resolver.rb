# typed: strict
# frozen_string_literal: true

require "json"
require "excon"
require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class GoModulesVersionResolver
        extend T::Sig

        PROXY_BASE_URL = "https://proxy.golang.org"

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
          @module_path = T.let(dependency.name, String)
        end

        sig { returns(T.nilable(String)) }
        def latest_version
          versions = fetch_versions
          return nil if versions.empty?

          valid_versions = versions.reject { |v| retracted?(v) || pseudo_version?(v) }
          return nil if valid_versions.empty?

          valid_versions.max_by { |v| version_sort_key(v) }
        end

        sig { returns(T::Array[String]) }
        def fetch_versions
          url = "#{PROXY_BASE_URL}/#{@module_path}/@v/list"
          response = Excon.get(url, idempotent: true, **SharedHelpers.excon_defaults)

          return [] unless response.status == 200

          response.body.split("\n").map(&:strip).reject(&:empty?)
        rescue Excon::Error, JSON::ParserError => e
          Dependabot.logger.warn("Failed to fetch Go versions for #{@module_path}: #{e.message}")
          []
        end

        sig { params(version: String).returns(T::Boolean) }
        def retracted?(version)
          url = "#{PROXY_BASE_URL}/#{@module_path}/@v/#{version}.info"
          response = Excon.get(url, idempotent: true, **SharedHelpers.excon_defaults)

          return false unless response.status == 200

          info = JSON.parse(response.body)
          info["Retracted"] == true
        rescue JSON::ParserError, Excon::Error::Timeout
          false
        end

        sig { params(version: String).returns(T::Boolean) }
        def pseudo_version?(version)
          version.match?(/v\d+\.\d+\.\d+-\d{14}-[0-9a-f]{12}/)
        end

        private

        sig { params(version: String).returns(T::Array[T.any(Integer, String)]) }
        def version_sort_key(version)
          cleaned = version.gsub(/^v/, "")
          parts = cleaned.split(/[.\-+]/)

          parts.map do |part|
            part.match?(/^\d+$/) ? part.to_i : part
          end
        end
      end
    end
  end
end
