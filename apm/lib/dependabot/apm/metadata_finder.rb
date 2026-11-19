# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"
require "dependabot/apm/package_specifier"

module Dependabot
  module Apm
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # Hosts whose canonical git provider lets us rebuild the Source from the
      # full repository path. Dependabot::Source.from_url caps the repo at three
      # path segments and is not end-anchored, so a deep GitLab namespace such as
      # `group/subgroup/team/project` would be truncated to `group/subgroup/team`
      # and resolve to the wrong source/changelog. APM already knows the complete
      # path via PackageSpecifier, so we bypass that regex for these hosts.
      PROVIDER_BY_HOST = T.let(
        {
          "github.com" => "github",
          "gitlab.com" => "gitlab",
          "bitbucket.org" => "bitbucket"
        }.freeze,
        T::Hash[String, String]
      )

      # The API path each provider serves under its own authority. A dependency
      # may pin a custom port (`github.com:8443`), which is a distinct endpoint
      # from the public SaaS host: it is a self-hosted-style install whose API is
      # served from the same authority (mirroring Dependabot::Source's GitHub
      # Enterprise `…/api/v3` handling), not from the public `api.github.com`.
      # Used only when a port is present; portless canonical hosts keep the
      # provider's public defaults.
      API_PATH_BY_PROVIDER = T.let(
        {
          "github" => "api/v3",
          "gitlab" => "api/v4",
          "bitbucket" => "2.0"
        }.freeze,
        T::Hash[String, String]
      )

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        url = dependency.requirements.first&.source_string("url")
        return unless url

        source_from_full_path(url) || Source.from_url(url)
      end

      # Builds the Source directly from the full repository path so nested
      # namespaces survive, falling back (via the caller) to Source.from_url for
      # hosts we cannot resolve a provider for (e.g. self-hosted installs).
      sig { params(url: String).returns(T.nilable(Dependabot::Source)) }
      def source_from_full_path(url)
        spec = Dependabot::Apm::PackageSpecifier.parse(url)
        return unless spec

        # Classify by the hostname alone: a custom port is transport, not a
        # different provider, so `github.com:8443` is still GitHub.
        hostname = Dependabot::Apm::PackageSpecifier.hostname_without_port(spec.host)
        provider = PROVIDER_BY_HOST[hostname]
        return if provider.nil? || spec.repo.empty?

        repo = "#{spec.owner}/#{spec.repo}"
        # A portless canonical host uses the provider's public defaults.
        return Dependabot::Source.new(provider: provider, repo: repo) if spec.host == hostname

        # A custom port is a distinct, self-hosted-style endpoint: preserve the
        # full authority and its matching API so source and changelog links
        # target it. Passing the URL to Source.from_url instead would misread the
        # port as part of the repo path (`github.com:8443/org/repo` -> `8443/org`).
        Dependabot::Source.new(
          provider: provider,
          repo: repo,
          hostname: spec.host,
          api_endpoint: "https://#{spec.host}/#{API_PATH_BY_PROVIDER.fetch(provider)}"
        )
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("apm", Dependabot::Apm::MetadataFinder)
