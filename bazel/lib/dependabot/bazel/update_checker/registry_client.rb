# typed: strict
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require "dependabot/dependency"
require "dependabot/errors"

module Dependabot
  module Bazel
    class UpdateChecker
      class RegistryClient
        extend T::Sig

        GITHUB_API_BASE = "https://api.github.com/repos/bazelbuild/bazel-central-registry"
        RAW_BASE = "https://raw.githubusercontent.com/bazelbuild/bazel-central-registry/main"

        sig { params(module_name: String).returns(T::Array[String]) }
        def all_module_versions(module_name)
          url = "#{GITHUB_API_BASE}/contents/modules/#{module_name}"
          response = fetch_github_api(url)
          return [] unless response

          unless response.is_a?(Array)
            Dependabot.logger.warn("Expected array for module versions, got #{response.class}")
            return []
          end

          versions = response.filter_map do |item|
            next unless item.is_a?(Hash)
            next unless item["type"] == "dir"

            item["name"]
          end

          versions.sort_by { |v| version_sort_key(v) }
        rescue Dependabot::DependabotError => e
          raise e unless e.message.include?("404")

          Dependabot.logger.info("Module '#{module_name}' not found in registry")
          []
        end

        sig { params(module_name: String).returns(T.nilable(String)) }
        def latest_module_version(module_name)
          versions = all_module_versions(module_name)
          return nil if versions.empty?

          versions.max_by { |v| version_sort_key(v) }
        end

        sig { params(module_name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def get_metadata(module_name)
          versions = all_module_versions(module_name)
          return nil if versions.empty?

          {
            "name" => module_name,
            "versions" => versions,
            "latest_version" => latest_module_version(module_name)
          }
        end

        sig { params(module_name: String, version: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def get_source(module_name, version)
          url = "#{RAW_BASE}/modules/#{module_name}/#{version}/source.json"
          response = fetch_raw_content(url)
          return nil unless response

          JSON.parse(response)
        rescue JSON::ParserError => e
          Dependabot.logger.warn("Failed to parse source for #{module_name}@#{version}: #{e.message}")
          nil
        end

        sig { params(module_name: String, version: String).returns(T.nilable(String)) }
        def get_module_bazel(module_name, version)
          url = "#{RAW_BASE}/modules/#{module_name}/#{version}/MODULE.bazel"
          fetch_raw_content(url)
        end

        sig { params(module_name: String, version: String).returns(T::Boolean) }
        def module_version_exists?(module_name, version)
          !get_source(module_name, version).nil?
        end

        sig { params(module_name: String, version: String).returns(T.nilable(Time)) }
        def get_version_release_date(module_name, version)
          path = "modules/#{module_name}/#{version}"
          url = "#{GITHUB_API_BASE}/commits?path=#{path}&per_page=1"

          response = fetch_github_api(url)
          return nil if response.nil? || response.empty?

          commit = response.first
          commit_date = commit.dig("commit", "committer", "date")
          return nil unless commit_date

          Time.parse(commit_date)
        rescue StandardError => e
          Dependabot.logger.warn("Failed to fetch release date for #{module_name} v#{version}: #{e.message}")
          nil
        end

        private

        sig { params(url: String).returns(T.untyped) }
        def fetch_github_api(url)
          uri = URI.parse(url)
          http = Net::HTTP.new(T.must(uri.host), uri.port)
          http.use_ssl = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Get.new(uri.path || "/")
          request["User-Agent"] = "Dependabot"
          request["Accept"] = "application/vnd.github.v3+json"

          response = http.request(request)

          case response.code
          when "200"
            JSON.parse(response.body)
          when "404"
            nil
          else
            raise Dependabot::DependabotError,
                  "HTTP #{response.code} from GitHub API: #{response.message}"
          end
        rescue Net::HTTPError, SocketError, Timeout::Error => e
          Dependabot.logger.warn("Failed to fetch #{url}: #{e.message}")
          raise Dependabot::DependabotError, "GitHub API request failed: #{e.message}"
        rescue JSON::ParserError => e
          Dependabot.logger.warn("Failed to parse GitHub API response: #{e.message}")
          raise Dependabot::DependabotError, "Invalid JSON response from GitHub API"
        end

        sig { params(url: String).returns(T.nilable(String)) }
        def fetch_raw_content(url)
          uri = URI.parse(url)
          http = Net::HTTP.new(T.must(uri.host), uri.port)
          http.use_ssl = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Get.new(uri.path || "/")
          request["User-Agent"] = "Dependabot"

          response = http.request(request)

          case response.code
          when "200"
            response.body
          when "404"
            nil
          else
            raise Dependabot::DependabotError,
                  "HTTP #{response.code} from GitHub: #{response.message}"
          end
        rescue Net::HTTPError, SocketError, Timeout::Error => e
          Dependabot.logger.warn("Failed to fetch #{url}: #{e.message}")
          raise Dependabot::DependabotError, "GitHub request failed: #{e.message}"
        end

        sig { params(version: String).returns(T::Array[Integer]) }
        def version_sort_key(version)
          cleaned = version.gsub(/^v/, "")
          parts = cleaned.split(".")
          parts.map { |part| part.match?(/^\d+$/) ? part.to_i : 0 }
        end
      end
    end
  end
end
