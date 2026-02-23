# typed: strong
# frozen_string_literal: true

# Maps Dependabot package manager names to Dependency Graph ecosystem identifiers.
#
# Any Dependabot package manager that hasn't been configured for snapshotting will
# return an ecosystem value of 'other'.
module GithubApi
  class EcosystemMapper
    extend T::Sig

    UNMAPPED_ECOSYSTEM = T.let("other", String)

    # Mapping from Dependency Graph ecosystem to Dependabot package managers.
    ECOSYSTEM_TO_PACKAGE_MANAGERS = T.let({
      "rubygems" => %w(bundler),
      "npm" => %w(npm_and_yarn bun),
      "pypi" => %w(pip uv),
      "golang" => %w(go_modules),
      "maven" => %w(maven),
      "gradle" => %w(gradle),
      "nuget" => %w(nuget)
    }.freeze, T::Hash[String, T::Array[String]])

    # Inverted lookup: package_manager => ecosystem
    PACKAGE_MANAGER_TO_ECOSYSTEM = T.let(
      ECOSYSTEM_TO_PACKAGE_MANAGERS.each_with_object({}) do |(ecosystem, managers), map|
        managers.each { |pm| map[pm] = ecosystem }
      end.freeze,
      T::Hash[String, String]
    )

    sig { params(package_manager: String).returns(String) }
    def self.ecosystem_for(package_manager)
      ecosystem = PACKAGE_MANAGER_TO_ECOSYSTEM[package_manager]

      if ecosystem.nil?
        Dependabot.logger.warn(<<~WARN.chomp)
          Unknown Dependency Graph ecosystem for package manager: #{package_manager}

          The GithubApi::EcosystemMapper needs to be updated to map this package manager to a Dependency Graph package ecosystem.
        WARN
        return UNMAPPED_ECOSYSTEM
      end

      ecosystem
    end
  end
end
