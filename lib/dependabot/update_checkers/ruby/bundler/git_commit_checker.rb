# frozen_string_literal: true

require "octokit"
require "dependabot/metadata_finders/ruby/bundler"
require "dependabot/update_checkers/ruby/bundler"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class GitCommitChecker
          VERSION_REGEX = /[0-9]+(?:\.[a-zA-Z0-9]+)*/

          def initialize(dependency:, github_access_token:)
            @dependency = dependency
            @github_access_token = github_access_token
          end

          def commit_now_in_release?
            return @released if @previously_checked
            @previously_checked = true

            @released = perform_check
          end

          private

          attr_reader :dependency, :github_access_token

          def perform_check
            return false unless pinned_git_dependency?
            return false if rubygems_listing_source_url.nil?
            return false unless rubygems_source_hosted_on_github?

            most_recent_git_tag_includes_pinned_reference?
          end

          def pinned_git_dependency?
            git_dependency? && pinned?
          end

          def git_dependency?
            return false if dependency_source_details.nil?

            dependency_source_details.fetch(:type) == "git"
          end

          def pinned?
            return false unless git_dependency?

            dependency_source_details.fetch(:ref) !=
              dependency_source_details.fetch(:branch)
          end

          def most_recent_git_tag_includes_pinned_reference?
            return false if most_recent_git_tag.nil?

            github_client.compare(
              rubygems_source_repo,
              most_recent_git_tag.name,
              pinned_ref
            ).status == "behind"
          rescue Octokit::NotFound
            false
          end

          def pinned_ref
            return false unless pinned?
            dependency_source_details.fetch(:ref)
          end

          def dependency_source_details
            sources =
              dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

            raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

            sources.first
          end

          def rubygems_listing_source_url
            @rubygems_listing_source_url ||=
              begin
                # Remove the git source, so the MetadataFinder looks on Rubygems
                candidate_dep = Dependency.new(
                  name: dependency.name,
                  version: dependency.version,
                  requirements: [],
                  package_manager: dependency.package_manager
                )

                MetadataFinders::Ruby::Bundler.new(
                  dependency: candidate_dep,
                  github_client: github_client
                ).source_url
              end
          end

          def rubygems_source_hosted_on_github?
            rubygems_listing_source_url.start_with?(github_client.web_endpoint)
          end

          def rubygems_source_repo
            rubygems_listing_source_url.gsub(github_client.web_endpoint, "")
          end

          def most_recent_git_tag
            @most_recent_git_tag ||=
              github_client.tags(rubygems_source_repo, per_page: 100).
              reverse.
              sort_by do |tag|
                next Gem::Version.new(0) unless tag.name.match?(VERSION_REGEX)

                begin
                  Gem::Version.new(tag.name.match(VERSION_REGEX).to_s)
                rescue ArgumentError
                  Gem::Version.new(0)
                end
              end.last
          end

          def github_client
            @github_client ||=
              Octokit::Client.new(access_token: github_access_token)
          end
        end
      end
    end
  end
end
