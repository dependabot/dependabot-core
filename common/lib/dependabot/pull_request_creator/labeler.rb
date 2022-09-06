# frozen_string_literal: true

require "octokit"
require "dependabot/pull_request_creator"
module Dependabot
  class PullRequestCreator
    class Labeler
      DEPENDENCIES_LABEL_REGEX = %r{^[^/]*dependenc[^/]+$}i.freeze
      DEFAULT_DEPENDENCIES_LABEL = "dependencies"
      DEFAULT_SECURITY_LABEL = "security"

      @package_manager_labels = {}

      class << self
        attr_reader :package_manager_labels

        def label_details_for_package_manager(package_manager)
          label_details = @package_manager_labels[package_manager]
          return label_details if label_details

          raise "Unsupported package_manager #{package_manager}"
        end

        def register_label_details(package_manager, label_details)
          @package_manager_labels[package_manager] = label_details
        end
      end

      def initialize(source:, custom_labels:, credentials:, dependencies:,
                     includes_security_fixes:, label_language:,
                     automerge_candidate:)
        @source                  = source
        @custom_labels           = custom_labels
        @credentials             = credentials
        @dependencies            = dependencies
        @includes_security_fixes = includes_security_fixes
        @label_language          = label_language
        @automerge_candidate     = automerge_candidate
      end

      def create_default_labels_if_required
        create_default_dependencies_label_if_required
        create_default_security_label_if_required
        create_default_language_label_if_required
      end

      def labels_for_pr
        [
          *default_labels_for_pr,
          includes_security_fixes? ? security_label : nil,
          label_update_type? ? semver_label : nil,
          automerge_candidate? ? automerge_label : nil
        ].compact.uniq
      end

      def label_pull_request(pull_request_number)
        create_default_labels_if_required

        return if labels_for_pr.none?
        raise "Only GitHub!" unless source.provider == "github"

        github_client_for_source.add_labels_to_an_issue(
          source.repo,
          pull_request_number,
          labels_for_pr
        )
      rescue Octokit::UnprocessableEntity, Octokit::NotFound
        retry_count ||= 0
        retry_count += 1
        raise if retry_count > 10

        sleep(rand(1..1.99))
        retry
      end

      private

      attr_reader :source, :custom_labels, :credentials, :dependencies

      def label_language?
        @label_language
      end

      def includes_security_fixes?
        @includes_security_fixes
      end

      def automerge_candidate?
        @automerge_candidate
      end

      def update_type
        return unless dependencies.any?(&:previous_version)

        case precision
        when 0 then "non-semver"
        when 1 then "major"
        when 2 then "minor"
        when 3 then "patch"
        end
      end

      def precision
        dependencies.map do |dep|
          new_version_parts = version(dep).split(/[.+]/)
          old_version_parts = previous_version(dep)&.split(/[.+]/) || []
          all_parts = new_version_parts.first(3) + old_version_parts.first(3)
          # rubocop:disable Performance/RedundantEqualityComparisonBlock
          next 0 unless all_parts.all? { |part| part.to_i.to_s == part }
          # rubocop:enable Performance/RedundantEqualityComparisonBlock
          next 1 if new_version_parts[0] != old_version_parts[0]
          next 2 if new_version_parts[1] != old_version_parts[1]

          3
        end.min
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def version(dep)
        return dep.version if version_class.correct?(dep.version)

        source = dep.requirements.find { |r| r.fetch(:source) }&.fetch(:source)
        type = source&.fetch("type", nil) || source&.fetch(:type)
        return dep.version unless type == "git"

        ref = source.fetch("ref", nil) || source.fetch(:ref)
        version_from_ref = ref&.gsub(/^v/, "")
        return dep.version unless version_from_ref
        return dep.version unless version_class.correct?(version_from_ref)

        version_from_ref
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # rubocop:disable Metrics/PerceivedComplexity
      def previous_version(dep)
        version_str = dep.previous_version
        return version_str if version_class.correct?(version_str)

        source = dep.previous_requirements.
                 find { |r| r.fetch(:source) }&.fetch(:source)
        type = source&.fetch("type", nil) || source&.fetch(:type)
        return version_str unless type == "git"

        ref = source.fetch("ref", nil) || source.fetch(:ref)
        version_from_ref = ref&.gsub(/^v/, "")
        return version_str unless version_from_ref
        return version_str unless version_class.correct?(version_from_ref)

        version_from_ref
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def create_default_dependencies_label_if_required
        return if custom_labels
        return if dependencies_label_exists?

        create_dependencies_label
      end

      def create_default_security_label_if_required
        return unless includes_security_fixes?
        return if security_label_exists?

        create_security_label
      end

      def create_default_language_label_if_required
        return unless label_language?
        return if custom_labels
        return if language_label_exists?

        create_language_label
      end

      def default_labels_for_pr
        if custom_labels then custom_labels & labels
        else
          [
            default_dependencies_label,
            label_language? ? language_label : nil
          ].compact
        end
      end

      # Find the exact match first and then fallback to *dependenc* label
      def default_dependencies_label
        labels.find { |l| l == DEFAULT_DEPENDENCIES_LABEL } ||
          labels.find { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }
      end

      def dependencies_label_exists?
        labels.any? { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }
      end

      def security_label_exists?
        !security_label.nil?
      end

      # Find the exact match first and then fallback to * security* label
      def security_label
        labels.find { |l| l == DEFAULT_SECURITY_LABEL } ||
          labels.find { |l| l.match?(/security/i) }
      end

      def label_update_type?
        # If a `skip-release` label exists then this repo is likely to be using
        # an auto-releasing service (like auto). We don't want to hijack that
        # service's labels.
        return false if labels.map(&:downcase).include?("skip-release")

        # Otherwise, check whether labels exist for each update type
        (%w(major minor patch) - labels.map(&:downcase)).empty?
      end

      def semver_label
        return unless update_type

        labels.find { |l| l.downcase == update_type.to_s }
      end

      def automerge_label
        labels.find { |l| l.casecmp("automerge").zero? }
      end

      def language_label_exists?
        !language_label.nil?
      end

      def language_label
        label_name =
          self.class.label_details_for_package_manager(package_manager).
          fetch(:name)
        labels.find { |l| l.casecmp(label_name).zero? }
      end

      def labels
        @labels ||=
          case source.provider
          when "github" then fetch_github_labels
          when "gitlab" then fetch_gitlab_labels
          when "azure" then fetch_azure_labels
          else raise "Unsupported provider #{source.provider}"
          end
      end

      def fetch_github_labels
        client = github_client_for_source

        labels =
          client.
          labels(source.repo, per_page: 100).
          map(&:name)

        next_link = client.last_response.rels[:next]

        while next_link
          next_page = next_link.get
          labels += next_page.data.map(&:name)
          next_link = next_page.rels[:next]
        end

        labels
      end

      def fetch_gitlab_labels
        gitlab_client_for_source.
          labels(source.repo, per_page: 100).
          auto_paginate.
          map(&:name)
      end

      def fetch_azure_labels
        langauge_name =
          self.class.label_details_for_package_manager(package_manager).
          fetch(:name)

        @labels = [
          *@labels,
          DEFAULT_DEPENDENCIES_LABEL,
          DEFAULT_SECURITY_LABEL,
          langauge_name
        ].uniq
      end

      def create_dependencies_label
        case source.provider
        when "github" then create_github_dependencies_label
        when "gitlab" then create_gitlab_dependencies_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_security_label
        case source.provider
        when "github" then create_github_security_label
        when "gitlab" then create_gitlab_security_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_language_label
        case source.provider
        when "github" then create_github_language_label
        when "gitlab" then create_gitlab_language_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      def create_github_dependencies_label
        github_client_for_source.add_label(
          source.repo, DEFAULT_DEPENDENCIES_LABEL, "0366d6",
          description: "Pull requests that update a dependency file",
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      end

      def create_gitlab_dependencies_label
        gitlab_client_for_source.create_label(
          source.repo, DEFAULT_DEPENDENCIES_LABEL, "#0366d6",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      end

      def create_github_security_label
        github_client_for_source.add_label(
          source.repo, DEFAULT_SECURITY_LABEL, "ee0701",
          description: "Pull requests that address a security vulnerability",
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      end

      def create_gitlab_security_label
        gitlab_client_for_source.create_label(
          source.repo, DEFAULT_SECURITY_LABEL, "#ee0701",
          description: "Pull requests that address a security vulnerability"
        )
        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      end

      def create_github_language_label
        label = self.class.label_details_for_package_manager(package_manager)
        language_name = label.fetch(:name)
        github_client_for_source.add_label(
          source.repo,
          language_name,
          label.fetch(:colour),
          description: label.fetch(:description) { default_description_for(language_name) },
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, language_name].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, language_name].uniq
      end

      def default_description_for(language)
        "Pull requests that update #{language.capitalize} code"
      end

      def create_gitlab_language_label
        langauge_name =
          self.class.label_details_for_package_manager(package_manager).
          fetch(:name)
        gitlab_client_for_source.create_label(
          source.repo,
          langauge_name,
          "#" + self.class.label_details_for_package_manager(package_manager).
                fetch(:colour)
        )
        @labels = [*@labels, langauge_name].uniq
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def package_manager
        @package_manager ||= dependencies.first.package_manager
      end

      def version_class
        Utils.version_class_for_package_manager(package_manager)
      end
    end
  end
end
