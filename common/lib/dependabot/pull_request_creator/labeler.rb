# typed: strict
# frozen_string_literal: true

require "octokit"
require "sorbet-runtime"
require "dependabot/pull_request_creator"
require "dependabot/credential"

module Dependabot
  class PullRequestCreator
    # rubocop:disable Metrics/ClassLength
    class Labeler
      extend T::Sig

      DEPENDENCIES_LABEL_REGEX = %r{^[^/]*dependenc[^/]+$}i
      DEFAULT_DEPENDENCIES_LABEL = "dependencies"
      DEFAULT_SECURITY_LABEL = "security"

      @package_manager_labels = T.let({}, T::Hash[String, T::Hash[Symbol, String]])

      class << self
        extend T::Sig

        sig { returns(T::Hash[String, T::Hash[Symbol, String]]) }
        attr_reader :package_manager_labels

        sig { params(package_manager: String).returns(T::Hash[Symbol, String]) }
        def label_details_for_package_manager(package_manager)
          label_details = @package_manager_labels[package_manager]
          return label_details if label_details

          raise "Unsupported package_manager #{package_manager}"
        end

        sig { params(package_manager: String, label_details: T::Hash[Symbol, String]).void }
        def register_label_details(package_manager, label_details)
          @package_manager_labels[package_manager] = label_details
        end
      end

      sig do
        params(
          source: Dependabot::Source,
          custom_labels: T.nilable(T::Array[String]),
          credentials: T::Array[Dependabot::Credential],
          dependencies: T::Array[Dependency],
          includes_security_fixes: T::Boolean,
          label_language: T::Boolean,
          automerge_candidate: T::Boolean
        )
          .void
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

      sig { void }
      def create_default_labels_if_required
        create_default_dependencies_label_if_required
        create_default_security_label_if_required
        create_default_language_label_if_required
      end

      sig { returns(T::Array[String]) }
      def labels_for_pr
        [
          *default_labels_for_pr,
          includes_security_fixes? ? security_label : nil,
          label_update_type? ? semver_label : nil,
          automerge_candidate? ? automerge_label : nil
        ].compact.uniq
      end

      sig { params(pull_request_number: Integer).void }
      def label_pull_request(pull_request_number)
        create_default_labels_if_required

        return if labels_for_pr.none?
        raise "Only GitHub!" unless source.provider == "github"

        T.unsafe(github_client_for_source).add_labels_to_an_issue(
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

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :custom_labels

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Boolean) }
      def label_language?
        @label_language
      end

      sig { returns(T::Boolean) }
      def includes_security_fixes?
        @includes_security_fixes
      end

      sig { returns(T::Boolean) }
      def automerge_candidate?
        @automerge_candidate
      end

      sig { returns(T.nilable(String)) }
      def update_type
        return unless dependencies.any?(&:previous_version)

        case precision
        when 0 then "non-semver"
        when 1 then "major"
        when 2 then "minor"
        when 3 then "patch"
        end
      end

      sig { returns(Integer) }
      def precision
        T.must(dependencies.map do |dep|
          new_version_parts = T.must(version(dep)).split(/[.+]/)
          old_version_parts = previous_version(dep)&.split(/[.+]/) || []
          all_parts = new_version_parts.first(3) + old_version_parts.first(3)
          # rubocop:disable Performance/RedundantEqualityComparisonBlock
          next 0 unless all_parts.all? { |part| part.to_i.to_s == part }
          # rubocop:enable Performance/RedundantEqualityComparisonBlock
          next 1 if new_version_parts[0] != old_version_parts[0]
          next 2 if new_version_parts[1] != old_version_parts[1]

          3
        end.min)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
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
      sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
      def previous_version(dep)
        version_str = dep.previous_version
        return version_str if version_class.correct?(version_str)

        source = T.must(dep.previous_requirements)
                  .find { |r| r.fetch(:source) }&.fetch(:source)
        type = source&.fetch("type", nil) || source&.fetch(:type)
        return version_str unless type == "git"

        ref = source.fetch("ref", nil) || source.fetch(:ref)
        version_from_ref = ref&.gsub(/^v/, "")
        return version_str unless version_from_ref
        return version_str unless version_class.correct?(version_from_ref)

        version_from_ref
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T.nilable(T::Array[String])) }
      def create_default_dependencies_label_if_required
        return if custom_labels
        return if dependencies_label_exists?

        create_dependencies_label
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_default_security_label_if_required
        return unless includes_security_fixes?
        return if security_label_exists?

        create_security_label
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_default_language_label_if_required
        return unless label_language?
        return if custom_labels
        return if language_label_exists?

        create_language_label
      end

      sig { returns(T::Array[String]) }
      def default_labels_for_pr
        if custom_labels
          # Azure does not have centralised labels
          return T.must(custom_labels) if source.provider == "azure"

          T.must(custom_labels) & labels
        else
          [
            default_dependencies_label,
            label_language? ? language_label : nil
          ].compact
        end
      end

      # Find the exact match first and then fallback to *dependency* label
      sig { returns(T.nilable(String)) }
      def default_dependencies_label
        labels.find { |l| l == DEFAULT_DEPENDENCIES_LABEL } ||
          labels.find { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }
      end

      sig { returns(T::Boolean) }
      def dependencies_label_exists?
        labels.any? { |l| l.match?(DEPENDENCIES_LABEL_REGEX) }
      end

      sig { returns(T::Boolean) }
      def security_label_exists?
        !security_label.nil?
      end

      # Find the exact match first and then fallback to * security* label
      sig { returns(T.nilable(String)) }
      def security_label
        labels.find { |l| l == DEFAULT_SECURITY_LABEL } ||
          labels.find { |l| l.match?(/security/i) }
      end

      sig { returns(T::Boolean) }
      def label_update_type?
        # If a `skip-release` label exists then this repo is likely to be using
        # an auto-releasing service (like auto). We don't want to hijack that
        # service's labels.
        return false if labels.map(&:downcase).include?("skip-release")

        # Otherwise, check whether labels exist for each update type
        (%w(major minor patch) - labels.map(&:downcase)).empty?
      end

      sig { returns(T.nilable(String)) }
      def semver_label
        return unless update_type

        labels.find { |l| l.downcase == update_type.to_s }
      end

      sig { returns(T.nilable(String)) }
      def automerge_label
        labels.find { |l| l.casecmp("automerge")&.zero? }
      end

      sig { returns(T::Boolean) }
      def language_label_exists?
        !language_label.nil?
      end

      sig { returns(T.nilable(String)) }
      def language_label
        label_name =
          self.class.label_details_for_package_manager(package_manager)
              .fetch(:name)
        labels.find { |l| l.casecmp(label_name)&.zero? }
      end

      sig { returns(T::Array[String]) }
      def labels
        @labels ||= T.let(
          case source.provider
          when "github" then fetch_github_labels
          when "gitlab" then fetch_gitlab_labels
          when "azure" then fetch_azure_labels
          else raise "Unsupported provider #{source.provider}"
          end,
          T.nilable(T::Array[String])
        )
      end

      sig { returns(T::Array[String]) }
      def fetch_github_labels
        client = github_client_for_source

        labels =
          T.unsafe(client)
           .labels(source.repo, per_page: 100)
           .map(&:name)

        next_link = T.unsafe(client).last_response.rels[:next]

        while next_link
          next_page = next_link.get
          labels += next_page.data.map(&:name)
          next_link = next_page.rels[:next]
        end

        labels
      end

      sig { returns(T::Array[String]) }
      def fetch_gitlab_labels
        T.unsafe(gitlab_client_for_source)
         .labels(source.repo, per_page: 100)
         .auto_paginate
         .map(&:name)
      end

      sig { returns(T::Array[String]) }
      def fetch_azure_labels
        language_name =
          self.class.label_details_for_package_manager(package_manager)
              .fetch(:name)

        @labels = [
          *@labels,
          DEFAULT_DEPENDENCIES_LABEL,
          DEFAULT_SECURITY_LABEL,
          language_name
        ].uniq
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_dependencies_label
        case source.provider
        when "github" then create_github_dependencies_label
        when "gitlab" then create_gitlab_dependencies_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_security_label
        case source.provider
        when "github" then create_github_security_label
        when "gitlab" then create_gitlab_security_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_language_label
        case source.provider
        when "github" then create_github_language_label
        when "gitlab" then create_gitlab_language_label
        when "azure" then @labels # Azure does not have centralised labels
        else raise "Unsupported provider #{source.provider}"
        end
      end

      sig { returns(T::Array[String]) }
      def create_github_dependencies_label
        T.unsafe(github_client_for_source).add_label(
          source.repo, DEFAULT_DEPENDENCIES_LABEL, "0366d6",
          description: "Pull requests that update a dependency file",
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      end

      sig { returns(T::Array[String]) }
      def create_gitlab_dependencies_label
        T.unsafe(gitlab_client_for_source).create_label(
          source.repo, DEFAULT_DEPENDENCIES_LABEL, "#0366d6",
          description: "Pull requests that update a dependency file"
        )
        @labels = [*@labels, DEFAULT_DEPENDENCIES_LABEL].uniq
      end

      sig { returns(T::Array[String]) }
      def create_github_security_label
        T.unsafe(github_client_for_source).add_label(
          source.repo, DEFAULT_SECURITY_LABEL, "ee0701",
          description: "Pull requests that address a security vulnerability",
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      end

      sig { returns(T.nilable(T::Array[String])) }
      def create_gitlab_security_label
        T.unsafe(gitlab_client_for_source).create_label(
          source.repo, DEFAULT_SECURITY_LABEL, "#ee0701",
          description: "Pull requests that address a security vulnerability"
        )
        @labels = [*@labels, DEFAULT_SECURITY_LABEL].uniq
      end

      sig { returns(T::Array[String]) }
      def create_github_language_label
        label = self.class.label_details_for_package_manager(package_manager)
        language_name = label.fetch(:name)
        T.unsafe(github_client_for_source).add_label(
          source.repo,
          language_name,
          label.fetch(:colour),
          description: label.fetch(:description) { default_description_for(language_name) },
          accept: "application/vnd.github.symmetra-preview+json"
        )
        @labels = [*@labels, language_name].uniq
      rescue Octokit::UnprocessableEntity => e
        raise unless e.errors.first.fetch(:code) == "already_exists"

        @labels = [*@labels, language_name].uniq.compact
      end

      sig { params(language: String).returns(String) }
      def default_description_for(language)
        "Pull requests that update #{language.capitalize} code"
      end

      sig { returns(T::Array[String]) }
      def create_gitlab_language_label
        language_name =
          self.class.label_details_for_package_manager(package_manager)
              .fetch(:name)
        T.unsafe(gitlab_client_for_source).create_label(
          source.repo,
          language_name,
          "#" + self.class.label_details_for_package_manager(package_manager)
                .fetch(:colour)
        )
        @labels = [*@labels, language_name].uniq
      end

      sig { returns(Dependabot::Clients::GithubWithRetries) }
      def github_client_for_source
        @github_client_for_source ||= T.let(
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          ),
          T.nilable(Dependabot::Clients::GithubWithRetries)
        )
      end

      sig { returns(Dependabot::Clients::GitlabWithRetries) }
      def gitlab_client_for_source
        @gitlab_client_for_source ||= T.let(
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          ),
          T.nilable(Dependabot::Clients::GitlabWithRetries)
        )
      end

      sig { returns(String) }
      def package_manager
        @package_manager ||= T.let(T.must(dependencies.first).package_manager, T.nilable(String))
      end

      sig { returns(T.class_of(Dependabot::Version)) }
      def version_class
        Utils.version_class_for_package_manager(package_manager)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
