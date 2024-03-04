# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/update_checkers/version_filters"

module SilentPackageManager
  class UpdateChecker < Dependabot::UpdateCheckers::Base
    def latest_version
      return next_git_version if git_dependency?

      versions = available_versions
      versions = filter_ignored_versions(versions)
      versions.max.to_s
    end

    def latest_version_resolvable_with_full_unlock?
      # For ecosystems that have lockfiles, the updater allows an ecosystem to try progressively
      # more aggressive approaches to dependency unlocking. This method represents the most aggressive
      # approach that allows for updating all dependencies to try to get the target dependency to update.
      # We're going to let the specs handle testing that logic, returning false here.
      false
    end

    def lowest_security_fix_version
      versions = available_versions
      versions = filter_lower_versions(versions)
      Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
        versions,
        security_advisories
      ).min.to_s
    end

    def lowest_resolvable_security_fix_version
      raise "Dependency not vulnerable!" unless vulnerable?

      lowest_security_fix_version
    end

    def up_to_date?
      dependency.version == latest_version
    end

    def latest_resolvable_version
      latest_version
    end

    def updated_requirements
      dependency.requirements.map do |req|
        req.merge(requirement: preferred_resolvable_version)
      end
    end

    private

    def git_dependency?
      dependency.version&.length == 40
    end

    def next_git_version
      fetch_dependency_metadata["git"]
    end

    def filter_lower_versions(versions)
      versions.reject { |v| v < version_class.new(dependency.version) }
    end

    def filter_ignored_versions(versions)
      filtered = versions.reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
      return filtered unless versions.any? && filtered.empty? && raise_on_ignored

      raise Dependabot::AllVersionsIgnored
    end

    def fetch_dependency_metadata
      version_file = File.join(repo_contents_path, dependency.name)
      return { "versions" => [] } unless File.exist?(version_file)

      # the available versions are stored in a file in the repo
      # that's why this package manager is silent, makes no requests
      JSON.parse(File.read(version_file))
    rescue JSON::ParserError
      raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
    end

    def available_versions
      return @available_versions if defined? @available_versions

      versions = fetch_dependency_metadata["versions"]
      @available_versions = versions.map { |v| SilentPackageManager::Version.new(v) }
    end
  end
end

Dependabot::UpdateCheckers.register("silent", SilentPackageManager::UpdateChecker)
