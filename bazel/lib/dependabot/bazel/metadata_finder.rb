# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Bazel
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case source_type
        when :bazel_dep
          find_source_from_bcr
        when :http_archive
          find_source_from_http_archive
        when :git_repository
          find_source_from_git_repository
        end
      end

      sig { returns(Symbol) }
      def source_type
        return :bazel_dep if dependency.requirements.any? { |r| r[:source].nil? }

        source = T.let(dependency.requirements.first, T.nilable(T::Hash[Symbol, T.untyped]))
        return :bazel_dep unless source

        source_details = T.let(source[:source], T.nilable(T::Hash[Symbol, T.untyped]))
        return :bazel_dep unless source_details

        source_type_value = source_details[:type]
        case source_type_value
        when "http_archive" then :http_archive
        when "git_repository" then :git_repository
        else :unknown
        end
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_bcr
        version = dependency.version
        return nil unless version

        source_info = registry_client.get_source(dependency.name, version)
        return nil unless source_info

        url = T.let(source_info["url"], T.nilable(String))
        return nil unless url

        github_source = extract_github_source_from_url(url)
        return github_source if github_source

        Dependabot::Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_http_archive
        source = T.let(dependency.requirements.first, T.nilable(T::Hash[Symbol, T.untyped]))
        return nil unless source

        source_details = T.let(source[:source], T.nilable(T::Hash[Symbol, T.untyped]))
        return nil unless source_details

        url = T.let(source_details[:url], T.nilable(String))
        return nil unless url

        github_source = extract_github_source_from_url(url)
        return github_source if github_source

        Dependabot::Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_repository
        source = T.let(dependency.requirements.first, T.nilable(T::Hash[Symbol, T.untyped]))
        return nil unless source

        source_details = T.let(source[:source], T.nilable(T::Hash[Symbol, T.untyped]))
        return nil unless source_details

        remote_url = T.let(source_details[:remote], T.nilable(String))
        return nil unless remote_url

        Dependabot::Source.from_url(remote_url)
      end

      sig { params(url: String).returns(T.nilable(Dependabot::Source)) }
      def extract_github_source_from_url(url)
        github_patterns = [
          %r{github\.com/([^/]+)/([^/]+)/archive},
          %r{github\.com/([^/]+)/([^/]+)/releases},
          %r{github\.com/([^/]+)/([^/]+)}
        ]

        github_patterns.each do |pattern|
          match = url.match(pattern)
          next unless match

          repo_url = "https://github.com/#{match[1]}/#{match[2]}"
          source = Dependabot::Source.from_url(repo_url)
          return source if source
        end

        nil
      end

      sig { returns(Dependabot::Bazel::UpdateChecker::RegistryClient) }
      def registry_client
        unless defined?(Dependabot::Bazel::UpdateChecker::RegistryClient)
          require "dependabot/bazel/update_checker/registry_client"
        end

        @registry_client ||= T.let(
          Dependabot::Bazel::UpdateChecker::RegistryClient.new(credentials: credentials),
          T.nilable(Dependabot::Bazel::UpdateChecker::RegistryClient)
        )
      end
    end
  end
end

Dependabot::MetadataFinders.register("bazel", Dependabot::Bazel::MetadataFinder)
