# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "excon"
require "dependabot/logger"
require "dependabot/shared_helpers"

module Dependabot
  module GoModules
    # Helper class for resolving vanity imports and extracting git hosts
    # This can be used across the Go modules ecosystem (file updater, update checker, etc.)
    # to handle vanity imports that redirect to actual git repositories
    class VanityImportResolver
      extend T::Sig

      # Known public hosting providers that don't require vanity import resolution
      KNOWN_PUBLIC_HOSTS = T.let([
        "github.com",
        "gitlab.com",
        "bitbucket.org"
      ].freeze, T::Array[String])

      # Regex patterns for parsing git URLs from go-import meta tags
      GO_IMPORT_META_TAG_REGEX = T.let(
        /<meta[^>]*name=["']go-import["'][^>]*content=["']([^"']+)["']/,
        Regexp
      )

      GIT_URL_HOST_REGEX = T.let(
        %r{(?:ssh://git@|git@|https://)([^/\s:]+)},
        Regexp
      )

      # Regex for identifying potential vanity import paths
      VANITY_IMPORT_PATH_REGEX = T.let(
        %r{^[^/]+\.[^/]+/},
        Regexp
      )

      # HTTP request configuration
      GO_GET_QUERY_PARAM = "?go-get=1"
      CONNECT_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 10

      # Common vanity import git host prefix
      GIT_HOST_PREFIX = "git"

      sig { params(dependencies: T::Array[Dependabot::Dependency], credentials: T::Array[Dependabot::Credential]).void }
      def initialize(dependencies:, credentials:)
        @dependencies = dependencies
        @credentials = credentials
        @resolve_git_hosts = T.let(nil, T.nilable(T::Array[String]))
      end

      # Resolve vanity imports by fetching go-get=1 metadata, with fallback to prediction
      # Returns array of git hosts that need git rewrite rules configured
      # Results are memoized since dependencies don't change during processing
      sig { returns(T::Array[String]) }
      def resolve_git_hosts
        @resolve_git_hosts ||= perform_resolution
      end

      # Check if any of the dependencies are potential vanity imports
      sig { returns(T::Boolean) }
      def vanity_imports?
        vanity_dependencies.any?
      end

      # Get only the dependencies that are potential vanity imports
      sig { returns(T::Array[Dependabot::Dependency]) }
      def vanity_dependencies
        @dependencies.select do |dep|
          path = dep.name
          # Skip known public hosting providers
          next false if KNOWN_PUBLIC_HOSTS.any? { |host| path.start_with?("#{host}/") }

          # Check if this looks like a vanity import (has domain with dots)
          path.match?(VANITY_IMPORT_PATH_REGEX)
        end
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      def perform_resolution
        return [] unless vanity_imports?

        git_hosts = Set.new

        vanity_dependencies.each do |dep|
          path = dep.name

          begin
            # Make authenticated HTTP request using Dependabot's credential system
            vanity_url = "https://#{path}#{GO_GET_QUERY_PARAM}"
            response = make_http_request(vanity_url)

            if response.status == 200
              resolved_hosts = extract_git_hosts_from_go_import_meta(response.body)
              if resolved_hosts.any?
                git_hosts.merge(resolved_hosts)
              else
                # Fall back to prediction if we can't parse the response
                domain = T.must(path.split("/").first)
                git_hosts.merge(predict_git_hosts_from_domain(domain))
              end
            else
              # Fall back to prediction for non-200 responses
              domain = T.must(path.split("/").first)
              git_hosts.merge(predict_git_hosts_from_domain(domain))
            end
          rescue StandardError => e
            # Fall back to prediction for any network/parsing errors
            Dependabot.logger.debug("Error resolving vanity import #{path}: #{e.message}, using prediction")
            domain = T.must(path.split("/").first)
            git_hosts.merge(predict_git_hosts_from_domain(domain))
          end
        end

        # Return all discovered git hosts - SharedHelpers.configure_git_to_use_https handles any host
        git_hosts.to_a
      end

      # Extract git hosts from all go-import meta tags in HTML response
      # A page can have multiple meta tags for different import prefixes
      # Example: <meta name="go-import" content="go.example.com/pkg git ssh://git@git.example.com/pkg">
      sig { params(html_body: String).returns(T::Array[String]) }
      def extract_git_hosts_from_go_import_meta(html_body)
        hosts = Set.new

        # Find all go-import meta tags
        html_body.scan(GO_IMPORT_META_TAG_REGEX) do |content_match|
          content = content_match[0]
          parts = content.split(/\s+/)
          next unless parts.length >= 3

          vcs_url = parts[2]

          # Extract host from various git URL formats:
          # ssh://git@git.example.com/repo → git.example.com
          # git@git.example.com:repo → git.example.com
          # https://git.example.com/repo → git.example.com
          if (host_match = vcs_url.match(GIT_URL_HOST_REGEX))
            hosts << host_match[1]
          end
        end

        hosts.to_a
      rescue StandardError => e
        Dependabot.logger.debug("Error parsing go-import meta tags: #{e.message}")
        []
      end

      # Fallback prediction logic for when vanity import resolution fails
      sig { params(domain: String).returns(T::Set[String]) }
      def predict_git_hosts_from_domain(domain)
        hosts = Set.new([domain])

        if domain.include?(".")
          parts = domain.split(".")
          if parts.length >= 2
            # Common pattern: go.company.com → git.company.com
            git_domain = [GIT_HOST_PREFIX] + T.must(parts[1..-1])
            hosts << git_domain.join(".")
          end
        end

        hosts
      rescue StandardError => e
        Dependabot.logger.debug("Error predicting git hosts for domain #{domain}: #{e.message}")
        Set.new([domain])
      end

      # Make HTTP request using Dependabot's standard HTTP configuration
      # The proxy handles credential injection automatically for configured hosts
      sig { params(url: String).returns(Excon::Response) }
      def make_http_request(url)
        Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults(
            connect_timeout: CONNECT_TIMEOUT_SECONDS,
            read_timeout: READ_TIMEOUT_SECONDS
          )
        )
      end
    end
  end
end
