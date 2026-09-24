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

        provider = PROVIDER_BY_HOST[spec.host]
        return if provider.nil? || spec.repo.empty?

        Dependabot::Source.new(provider: provider, repo: "#{spec.owner}/#{spec.repo}")
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("apm", Dependabot::Apm::MetadataFinder)
