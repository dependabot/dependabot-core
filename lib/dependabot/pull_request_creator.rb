# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/github"

    attr_reader :watched_repo, :dependencies, :files, :base_commit,
                :github_client, :pr_message_footer, :target_branch

    def initialize(repo:, base_commit:, dependencies:, files:, github_client:,
                   pr_message_footer: nil, target_branch: nil)
      @dependencies = dependencies
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
      @pr_message_footer = pr_message_footer
      @target_branch = target_branch

      check_dependencies_have_previous_version
    end

    def check_dependencies_have_previous_version
      return if library? && dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
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
      "chore(dependencies): " + pr_name + "\n\n" + pr_message
    end

    def pr_name
      return library_pr_name if library?

      base =
        if dependencies.count == 1
          dependency = dependencies.first
          "Bump #{dependency.name} from #{previous_version(dependency)} "\
          "to #{new_version(dependency)}"
        else
          names = dependencies.map(&:name)
          "Bump #{names[0..-2].join(', ')} and #{names[-1]}"
        end
      return base if files.first.directory == "/"

      base + " in #{files.first.directory}"
    end

    def library_pr_name
      if dependencies.count == 1
        "Update #{dependencies.first.name} requirement to "\
        "#{new_library_requirement(dependencies.first)}"
      else
        names = dependencies.map(&:name)
        "Update requirements for #{names[0..-2].join(', ')} and #{names[-1]}"
      end
    end

    def pr_message
      return requirement_pr_message if library?
      version_pr_message
    end

    def requirement_pr_message
      msg = "Updates the requirements on "

      names = dependencies.map do |dependency|
        if source_url(dependency)
          "[#{dependency.name}](#{source_url(dependency)})"
        elsif homepage_url
          "[#{dependency.name}](#{homepage_url(dependency)})"
        else
          dependency.name
        end
      end

      msg +=
        if dependencies.count == 1
          "#{names.first} "
        else
          "#{names[0..-2].join(', ')} and #{names[-1]} "
        end

      msg += "to permit the latest version."
      msg + metadata_links
    end

    def version_pr_message
      names = dependencies.map do |dependency|
        if source_url(dependency)
          "[#{dependency.name}](#{source_url(dependency)})"
        elsif homepage_url
          "[#{dependency.name}](#{homepage_url(dependency)})"
        else
          dependency.name
        end
      end

      if dependencies.count == 1
        dependency = dependencies.first
        msg = "Bumps #{names.first} from #{previous_version(dependency)} "\
              "to #{new_version(dependency)}."
        if switching_from_ref_to_release?(dependencies.first)
          msg += " This release includes the previously tagged commit."
        end
      else
        msg = "Bumps #{names[0..-2].join(', ')} and #{names[-1]}. These "\
        "dependencies needed to be updated at the same time."
      end

      msg + metadata_links
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def metadata_links
      msg = ""
      if dependencies.count == 1
        dep = dependencies.first
        msg += "\n- [Release notes](#{release_url(dep)})" if release_url(dep)
        msg += "\n- [Changelog](#{changelog_url(dep)})" if changelog_url(dep)
        msg += "\n- [Commits](#{commits_url(dep)})" if commits_url(dep)
      else
        dependencies.each do |d|
          if release_url(d)
            msg += "\n- [#{d.name} Release notes](#{release_url(d)})"
          end
          if changelog_url(d)
            msg += "\n- [#{d.name} Changelog](#{changelog_url(d)})"
          end
          if commits_url(d)
            msg += "\n- [#{d.name} Commits](#{commits_url(dep)})"
          end
        end
      end
      msg
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def pr_message_with_custom_footer
      return pr_message unless pr_message_footer
      pr_message + "\n\n#{pr_message_footer}"
    end

    def new_branch_name
      path = [
        "dependabot",
        dependencies.first.package_manager,
        files.first.directory
      ]
      path = path.compact

      if dependencies.count > 1
        File.join(*path, dependencies.map(&:name).join("-and-"))
      elsif library?
        dep = dependencies.first
        File.join(*path, "#{dep.name}-#{sanitized_requirement(dep)}")
      else
        dep = dependencies.first
        File.join(*path, "#{dep.name}-#{new_version(dep)}")
      end
    end

    def sanitized_requirement(dependency)
      new_library_requirement(dependency).
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

    def release_url(dependency)
      metadata_finder(dependency).release_url
    end

    def changelog_url(dependency)
      metadata_finder(dependency).changelog_url
    end

    def commits_url(dependency)
      metadata_finder(dependency).commits_url
    end

    def source_url(dependency)
      metadata_finder(dependency).source_url
    end

    def homepage_url(dependency)
      metadata_finder(dependency).homepage_url
    end

    def metadata_finder(dependency)
      @metadata_finder ||= {}
      @metadata_finder[dependency.name] ||=
        MetadataFinders.
        for_package_manager(dependency.package_manager).
        new(dependency: dependency, credentials: credentials)
    end

    def previous_version(dependency)
      if dependency.previous_version.match?(/^[0-9a-f]{40}$/)
        return previous_ref(dependency) if ref_changed?(dependency)
        dependency.previous_version[0..5]
      else
        dependency.previous_version
      end
    end

    def new_version(dependency)
      if dependency.version.match?(/^[0-9a-f]{40}$/)
        return new_ref(dependency) if ref_changed?(dependency)
        dependency.version[0..5]
      else
        dependency.version
      end
    end

    def previous_ref(dependency)
      dependency.previous_requirements.map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.compact.first
    end

    def new_ref(dependency)
      dependency.requirements.map do |r|
        r.dig(:source, "ref") || r.dig(:source, :ref)
      end.compact.first
    end

    def ref_changed?(dependency)
      previous_ref(dependency) && new_ref(dependency) &&
        previous_ref(dependency) != new_ref(dependency)
    end

    def new_library_requirement(dependency)
      updated_reqs = dependency.requirements - dependency.previous_requirements

      gemspec = updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
      return gemspec[:requirement] if gemspec
      updated_reqs.first[:requirement]
    end

    def credentials
      [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => github_client.access_token
        }
      ]
    end

    def library?
      if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return true
      end

      dependencies.none?(&:appears_in_lockfile?)
    end

    def requirements_changed?(dependency)
      (dependency.requirements - dependency.previous_requirements).any?
    end

    def switching_from_ref_to_release?(dependency)
      return false unless dependency.previous_version.match?(/^[0-9a-f]{40}$/)

      Gem::Version.new(dependency.version)
      true
    rescue ArgumentError
      false
    end
  end
end
