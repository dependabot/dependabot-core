# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Bazel
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      require_relative "update_checker/registry_client"

      GITHUB_URL_PATTERNS = T.let(
        [
          %r{github\.com/([^/]+)/([^/]+)/archive},
          %r{github\.com/([^/]+)/([^/]+)/releases},
          %r{github\.com/([^/]+)/([^/]+)}
        ].freeze,
        T::Array[Regexp]
      )

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
        when :unknown
          nil
        end
      end

      sig { returns(Symbol) }
      def source_type
        return :bazel_dep if dependency.requirements.empty?
        return :bazel_dep if dependency.requirements.any? { |r| r[:source].nil? }

        req = dependency.requirements.first
        return :bazel_dep unless req

        source_details = req[:source]
        return :bazel_dep unless source_details

        case source_details[:type]
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
        url = source_info&.dig("url")
        return nil unless url

        source_from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_http_archive
        req = dependency.requirements.first
        return nil unless req

        url = req.dig(:source, :url)
        return nil unless url

        source_from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_repository
        req = dependency.requirements.first
        return nil unless req

        remote_url = req.dig(:source, :remote)
        return nil unless remote_url

        Dependabot::Source.from_url(remote_url)
      end

      sig { params(url: String).returns(T.nilable(Dependabot::Source)) }
      def source_from_url(url)
        extract_github_source_from_url(url) || Dependabot::Source.from_url(url)
      end

      sig { params(url: String).returns(T.nilable(Dependabot::Source)) }
      def extract_github_source_from_url(url)
        pattern = GITHUB_URL_PATTERNS.find { |p| url.match?(p) }
        return nil unless pattern

        match = url.match(pattern)
        return nil unless match

        repo = match[2].sub(/\.git$/, "")
        repo_url = "https://github.com/#{match[1]}/#{repo}"

        Dependabot::Source.from_url(repo_url)
      end

      sig { returns(Dependabot::Bazel::UpdateChecker::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Bazel::UpdateChecker::RegistryClient.new(credentials: credentials),
          T.nilable(Dependabot::Bazel::UpdateChecker::RegistryClient)
        )
      end
    end
  end
end

Dependabot::MetadataFinders.register("bazel", Dependabot::Bazel::MetadataFinder)
