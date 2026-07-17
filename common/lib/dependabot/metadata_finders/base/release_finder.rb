# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "time"

require "dependabot/credential"
require "dependabot/clients/github_release"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/metadata_finders/base"
require "dependabot/utils"

module Dependabot
  module MetadataFinders
    class Base
      class GitLabRelease < T::ImmutableStruct
        extend T::Sig

        const :name, String
        const :tag_name, String
        const :body, T.nilable(String)
        const :html_url, String
        const :authored_at, Time

        sig do
          params(
            tag: Gitlab::ObjectifiedHash,
            source_url: String
          ).returns(T.nilable(GitLabRelease))
        end
        def self.from_tag(tag, source_url:)
          name = T.cast(tag["name"], Object)
          release = T.cast(tag["release"], Object)
          commit = T.cast(tag["commit"], Object)
          return unless name.is_a?(String)
          return unless release.is_a?(Gitlab::ObjectifiedHash)
          return unless commit.is_a?(Gitlab::ObjectifiedHash)

          tag_name = T.cast(release["tag_name"], Object)
          return unless tag_name.is_a?(String)

          authored_at = time_value(T.cast(commit["authored_date"], Object))
          return unless authored_at

          description = T.cast(release["description"], Object)
          new(
            name: name,
            tag_name: tag_name,
            body: description.is_a?(String) ? description : nil,
            html_url: "#{source_url}/tags/#{name}",
            authored_at: authored_at
          )
        end

        sig { params(value: Object).returns(T.nilable(Time)) }
        def self.time_value(value)
          return value if value.is_a?(Time)
          return unless value.is_a?(String)

          Time.parse(value)
        rescue ArgumentError
          nil
        end
        private_class_method :time_value
      end

      class ReleaseFinder
        extend T::Sig

        ReleaseType = T.type_alias { T.any(Dependabot::Clients::GithubRelease, GitLabRelease) }

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Source)) }
        attr_reader :source

        sig do
          params(
            source: T.nilable(Dependabot::Source),
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(T.nilable(String)) }
        def releases_url
          return unless source

          # Azure does not provide tags via API, so we can't check whether
          # there are any releases. So, optimistically return the tags location
          return "#{T.must(source).url}/tags" if T.must(source).provider == "azure"

          # If there are no releases, we won't be linking to the releases page
          return unless all_releases.any?

          case T.must(source).provider
          when "github" then "#{T.must(source).url}/releases"
          when "gitlab" then "#{T.must(source).url}/tags"
          when "bitbucket", "codecommit" then nil
          else raise "Unexpected repo provider '#{T.must(source).provider}'"
          end
        end

        sig { returns(T.nilable(String)) }
        def releases_text
          return unless relevant_releases&.any?
          return if relevant_releases&.all? { |r| r.body.nil? || r.body == "" }

          relevant_releases&.map { |r| serialize_release(r) }&.join("\n\n")
        end

        private

        sig { returns(T::Array[ReleaseType]) }
        def all_dep_releases
          releases = all_releases
          dep_prefix = dependency.name.downcase

          releases_with_dependency_name =
            releases
            .select { |r| r.tag_name.start_with?(dep_prefix) }

          return releases unless releases_with_dependency_name.any?

          releases_with_dependency_name
        end

        sig { returns(T::Array[ReleaseType]) }
        def all_releases
          @all_releases ||= T.let(fetch_dependency_releases, T.nilable(T::Array[ReleaseType]))
        end

        sig { returns(T.nilable(T::Array[ReleaseType])) }
        def relevant_releases
          releases = releases_since_previous_version

          # Sometimes we can't filter the releases properly (if they're
          # prefixed by a number that gets confused with the version). In this
          # case, the best we can do is return nil.
          return [] unless !releases.nil? && releases.any?

          if updated_release && version_class.correct?(new_version)
            releases = filter_releases_using_updated_release(releases)
            filter_releases_using_updated_version(T.must(releases), conservative: true)
          elsif updated_release
            filter_releases_using_updated_release(releases)
          elsif version_class.correct?(new_version)
            filter_releases_using_updated_version(releases, conservative: false)
          else
            [updated_release].compact
          end
        end

        sig { returns(T.nilable(T::Array[ReleaseType])) }
        def releases_since_previous_version
          return [updated_release].compact unless previous_version

          if previous_release && version_class.correct?(previous_version)
            releases = filter_releases_using_previous_release(all_dep_releases)
            filter_releases_using_previous_version(T.must(releases), conservative: true)
          elsif previous_release
            filter_releases_using_previous_release(all_dep_releases)
          elsif version_class.correct?(previous_version)
            filter_releases_using_previous_version(
              all_dep_releases,
              conservative: false
            )
          else
            [updated_release].compact
          end
        end

        sig { params(releases: T::Array[ReleaseType]).returns(T.nilable(T::Array[ReleaseType])) }
        def filter_releases_using_previous_release(releases)
          return releases if releases.index(previous_release).nil?

          releases.first(T.must(releases.index(previous_release)))
        end

        sig { params(releases: T::Array[ReleaseType]).returns(T.nilable(T::Array[ReleaseType])) }
        def filter_releases_using_updated_release(releases)
          return releases if releases.index(updated_release).nil?

          releases[releases.index(updated_release)..-1]
        end

        sig { params(releases: T::Array[ReleaseType], conservative: T::Boolean).returns(T::Array[ReleaseType]) }
        def filter_releases_using_previous_version(releases, conservative:)
          releases.reject do |release|
            cleaned_tag = release.tag_name.gsub(/^[^0-9]*/, "")
            cleaned_name = release.name&.gsub(/^[^0-9]*/, "")
            dot_count = [cleaned_tag, cleaned_name].compact.reject(&:empty?)
                                                   .map { |nm| nm.chars.count(".") }.max

            tag_version = [cleaned_tag, cleaned_name].compact.reject(&:empty?)
                                                     .select { |nm| version_class.correct?(nm) }
                                                     .select { |nm| nm.chars.count(".") == dot_count }
                                                     .map { |nm| version_class.new(nm) }.max

            next conservative unless tag_version

            # Reject any releases that are less than the previous version
            # (e.g., if two major versions are being maintained)
            tag_version <= version_class.new(previous_version)
          end
        end

        sig { params(releases: T::Array[ReleaseType], conservative: T::Boolean).returns(T::Array[ReleaseType]) }
        def filter_releases_using_updated_version(releases, conservative:)
          updated_version = version_class.new(new_version)

          releases.reject do |release|
            cleaned_tag = release.tag_name.gsub(/^[^0-9]*/, "")
            cleaned_name = release.name&.gsub(/^[^0-9]*/, "")
            dot_count = [cleaned_tag, cleaned_name].compact.reject(&:empty?)
                                                   .map { |nm| nm.chars.count(".") }.max

            tag_version = [cleaned_tag, cleaned_name].compact.reject(&:empty?)
                                                     .select { |nm| version_class.correct?(nm) }
                                                     .select { |nm| nm.chars.count(".") == dot_count }
                                                     .map { |nm| version_class.new(nm) }.min

            next conservative unless tag_version

            # Reject any releases that are greater than the updated version
            # (e.g., if two major versions are being maintained)
            tag_version > updated_version
          end
        end

        sig { returns(T.nilable(ReleaseType)) }
        def updated_release
          release_for_version(new_version)
        end

        sig { returns(T.nilable(ReleaseType)) }
        def previous_release
          release_for_version(previous_version)
        end

        sig { params(version: T.nilable(String)).returns(T.nilable(ReleaseType)) }
        def release_for_version(version)
          return nil unless version

          release_regex = version_regex(version)
          # Doing two loops looks inefficient, but it ensures consistency
          all_dep_releases.find { |r| release_regex.match?(r.tag_name.to_s) } ||
            all_dep_releases.find { |r| release_regex.match?(r.name.to_s) }
        end

        sig { params(release: ReleaseType).returns(String) }
        def serialize_release(release)
          name = release.name
          title = "## #{name.to_s == '' ? release.tag_name : name}\n"
          body = if release.body.to_s.gsub(/\n*\z/m, "") == ""
                   "No release notes provided."
                 else
                   T.must(release.body).gsub(/\n*\z/m, "")
                 end

          release_body_includes_title?(release) ? body : title + body
        end

        sig { params(release: ReleaseType).returns(T::Boolean) }
        def release_body_includes_title?(release)
          name = release.name
          title = name.nil? || name.empty? ? release.tag_name : name
          release.body.to_s.match?(/\A\s*\#*\s*#{Regexp.quote(title)}/m)
        end

        sig { params(version: T.nilable(String)).returns(Regexp) }
        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || 'unknown')}\z/
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T::Array[ReleaseType]) }
        def fetch_dependency_releases
          return [] unless source

          case T.must(source).provider
          when "github" then fetch_github_releases
          # Bitbucket and CodeCommit don't support releases and
          # Azure can't list API for annotated tags
          when "bitbucket", "azure", "codecommit", "example" then []
          when "gitlab" then fetch_gitlab_releases
          else raise "Unexpected repo provider '#{T.must(source).provider}'"
          end
        end

        sig { returns(T::Array[Dependabot::Clients::GithubRelease]) }
        def fetch_github_releases
          releases = parsed_github_releases

          clean_release_names =
            releases.map { |release| release.tag_name.gsub(/^[^0-9\.]*/, "") }

          if clean_release_names.all? { |nm| version_class.correct?(nm) }
            releases.sort_by do |release|
              version_class.new(release.tag_name.gsub(/^[^0-9\.]*/, ""))
            end.reverse
          else
            releases.sort_by { |release| release.id || 0 }.reverse
          end
        rescue Octokit::NotFound, Octokit::UnavailableForLegalReasons
          []
        end

        sig { returns(T::Array[Dependabot::Clients::GithubRelease]) }
        def parsed_github_releases
          resources = T.let(
            github_client.releases(T.must(source).repo, per_page: 100),
            T.nilable(T::Array[Sawyer::Resource])
          )
          releases = (resources || []).filter_map do |release|
            Dependabot::Clients::GithubRelease.from_resource(release)
          end
          releases
        end

        sig { returns(T::Array[GitLabRelease]) }
        def fetch_gitlab_releases
          tags = gitlab_client.tags(T.must(source).repo)
          releases = tags.filter_map do |tag|
            next unless tag.is_a?(Gitlab::ObjectifiedHash)

            GitLabRelease.from_tag(tag, source_url: T.must(source).url)
          end
          releases.sort_by(&:authored_at).reverse
        rescue Gitlab::Error::NotFound
          []
        end

        sig { returns(T.nilable(String)) }
        def previous_version
          # If we don't have a previous version, we *may* still be able to
          # figure one out if a ref was provided and has been changed (in which
          # case the previous ref was essentially the version).
          if dependency.previous_version.nil?
            return ref_changed? ? previous_ref : nil
          end

          # Previous version looks like a git SHA and there's a previous ref, we
          # could be changing to a nil previous ref in which case we want to
          # fall back to the sha version
          if T.must(dependency.previous_version).match?(/^[0-9a-f]{40}$/) &&
             ref_changed? && previous_ref
            previous_ref
          else
            dependency.previous_version
          end
        end

        sig { returns(T.nilable(String)) }
        def new_version
          # New version looks like a git SHA and there's a new ref, guarding
          # against changes to a nil new_ref (not certain this can actually
          # happen atm)
          if T.must(dependency.version).match?(/^[0-9a-f]{40}$/) && ref_changed? &&
             new_ref
            return new_ref
          end

          dependency.version
        end

        sig { returns(T.nilable(String)) }
        def previous_ref
          previous_refs = T.must(dependency.previous_requirements).filter_map do |requirement|
            requirement_ref(requirement)
          end.uniq
          previous_refs.first if previous_refs.one?
        end

        sig { returns(T.nilable(String)) }
        def new_ref
          new_refs = dependency.requirements.filter_map do |requirement|
            requirement_ref(requirement)
          end.uniq
          new_refs.first if new_refs.one?
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(String)) }
        def requirement_ref(requirement)
          source = requirement.source
          return unless source

          symbol_ref = T.cast(source[:ref], Object)
          return symbol_ref if symbol_ref.is_a?(String)

          string_ref = T.cast(source["ref"], Object)
          string_ref if string_ref.is_a?(String)
        end

        sig { returns(T::Boolean) }
        def ref_changed?
          # We could go from multiple previous refs (nil) to a single new ref
          previous_ref != new_ref
        end

        sig { returns(Dependabot::Clients::GitlabWithRetries) }
        def gitlab_client
          @gitlab_client ||=
            T.let(
              Dependabot::Clients::GitlabWithRetries.for_gitlab_dot_com(credentials: credentials),
              T.nilable(Dependabot::Clients::GitlabWithRetries)
            )
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||=
            T.let(
              Dependabot::Clients::GithubWithRetries.for_source(source: T.must(source), credentials: credentials),
              T.nilable(Dependabot::Clients::GithubWithRetries)
            )
        end
      end
    end
  end
end
