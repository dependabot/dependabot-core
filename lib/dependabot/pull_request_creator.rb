# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/github"

    attr_reader :watched_repo, :dependency, :files, :base_commit,
                :github_client, :pr_message_footer, :target_branch

    def initialize(repo:, base_commit:, dependency:, files:, github_client:,
                   pr_message_footer: nil, target_branch: nil)
      @dependency = dependency
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
      @pr_message_footer = pr_message_footer
      @target_branch = target_branch

      check_dependency_has_previous_version
    end

    def check_dependency_has_previous_version
      return if library? && requirements_changed?
      return if dependency.previous_version

      raise "Dependency must have a previous version or changed " \
            "requirement to have a pull request created for it!"
    end

    def create
      Github.new(
        repo_name: watched_repo,
        branch_name: new_branch_name,
        base_commit: base_commit,
        target_branch: target_branch,
        github_client: github_client,
        files: files,
        commit_message: commit_message,
        pr_description: pr_message_with_custom_footer,
        pr_name: pr_name
      ).create
    end

    private

    def commit_message
      pr_name + "\n\n" + pr_message
    end

    def pr_name
      return library_pr_name if library?

      base = "Bump #{dependency.name} from #{previous_version} " \
             "to #{new_version}"
      return base if files.first.directory == "/"

      base + " in #{files.first.directory}"
    end

    def library_pr_name
      "Update #{dependency.name} requirement to #{new_library_requirement}"
    end

    def pr_message
      return requirement_pr_message if library?
      version_pr_message
    end

    def version_pr_message
      msg = if source_url
              "Bumps [#{dependency.name}](#{source_url}) "
            elsif homepage_url
              "Bumps [#{dependency.name}](#{homepage_url}) "
            else
              "Bumps #{dependency.name} "
            end

      msg += "from #{previous_version} to #{new_version}."

      if switching_from_ref_to_release?
        msg += " This release includes the previously tagged commit."
      end

      msg + metadata_links
    end

    def metadata_links
      msg =  ""
      msg += "\n- [Release notes](#{release_url})" if release_url
      msg += "\n- [Changelog](#{changelog_url})" if changelog_url
      msg += "\n- [Commits](#{commits_url})" if commits_url
      msg
    end

    def requirement_pr_message
      msg = "Updates the requirements on "
      msg += if source_url
               "[#{dependency.name}](#{source_url}) "
             elsif homepage_url
               "[#{dependency.name}](#{homepage_url}) "
             else
               "#{dependency.name} "
             end

      msg += "to permit the latest version."
      msg + metadata_links
    end

    def pr_message_with_custom_footer
      return pr_message unless pr_message_footer
      pr_message + "\n\n#{pr_message_footer}"
    end

    def new_branch_name
      path = ["dependabot", dependency.package_manager, files.first.directory]
      path = path.compact

      if library?
        File.join(*path, "#{dependency.name}-#{sanitized_requirement}")
      else
        File.join(*path, "#{dependency.name}-#{new_version}")
      end
    end

    def sanitized_requirement
      new_library_requirement.
        delete(" ").
        gsub("!=", "neq-").
        gsub(">=", "gte-").
        gsub("<=", "lte-").
        gsub("~>", "tw-").
        gsub("~=", "tw-").
        gsub(/==*/, "eq-").
        gsub(">", "gt-").
        gsub("<", "lt-").
        gsub("*", "star").
        gsub(",", "-and-")
    end

    def release_url
      metadata_finder.release_url
    end

    def changelog_url
      metadata_finder.changelog_url
    end

    def commits_url
      metadata_finder.commits_url
    end

    def source_url
      metadata_finder.source_url
    end

    def homepage_url
      metadata_finder.homepage_url
    end

    def metadata_finder
      @metadata_finder ||=
        MetadataFinders.
        for_package_manager(dependency.package_manager).
        new(dependency: dependency, github_client: github_client)
    end

    def previous_version
      if dependency.previous_version.match?(/^[0-9a-f]{40}$/)
        return previous_ref if ref_changed?
        dependency.previous_version[0..5]
      else
        dependency.previous_version
      end
    end

    def new_version
      if dependency.version.match?(/^[0-9a-f]{40}$/)
        return new_ref if ref_changed?
        dependency.version[0..5]
      else
        dependency.version
      end
    end

    def previous_ref
      dependency.previous_requirements.map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.compact.first
    end

    def new_ref
      dependency.requirements.map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.compact.first
    end

    def ref_changed?
      previous_ref && new_ref && previous_ref != new_ref
    end

    def new_library_requirement
      updated_reqs = dependency.requirements - dependency.previous_requirements

      gemspec = updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
      return gemspec[:requirement] if gemspec
      updated_reqs.first[:requirement]
    end

    def library?
      if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return true
      end

      !dependency.appears_in_lockfile?
    end

    def requirements_changed?
      (dependency.requirements - dependency.previous_requirements).any?
    end

    def switching_from_ref_to_release?
      return false unless dependency.previous_version.match?(/^[0-9a-f]{40}$/)

      Gem::Version.new(dependency.version)
      true
    rescue ArgumentError
      false
    end
  end
end
