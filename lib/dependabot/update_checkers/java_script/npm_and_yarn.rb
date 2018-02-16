# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn < Dependabot::UpdateCheckers::Base
        require_relative "npm_and_yarn/requirements_updater"
        require_relative "npm_and_yarn/version"
        require_relative "npm_and_yarn/requirement"

        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          @latest_version ||= fetch_latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          # Javascript doesn't have the concept of version conflicts, so the
          # latest version is always resolvable.
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          if git_dependency?
            return latest_resolvable_version_with_no_unlock_for_git_dependency
          end

          reqs = dependency.requirements.map do |r|
            NpmAndYarn::Requirement.requirements_array(r.fetch(:requirement))
          end.compact

          (npm_details || {}).fetch("versions", {}).
            keys.map { |v| version_class.new(v) }.
            reject { |v| v.prerelease? && !wants_prerelease? }.sort.reverse.
            find do |version|
              reqs.all? { |r| r.any? { |opt| opt.satisfied_by?(version) } } &&
                !yanked?(version)
            end
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            updated_source: updated_source,
            latest_version:
              fetch_latest_version_details&.fetch(:version, nil)&.to_s,
            latest_resolvable_version:
              fetch_latest_version_details&.fetch(:version, nil)&.to_s,
            library: library?
          ).updated_requirements
        end

        def version_class
          NpmAndYarn::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for JS (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_resolvable_version_with_no_unlock_for_git_dependency
          reqs = dependency.requirements.map do |r|
            NpmAndYarn::Requirement.requirements_array(r.fetch(:requirement))
          end.compact

          return dependency.version if git_commit_checker.pinned?

          # TODO: Really we should get a tag that satisfies the semver req
          return dependency.version if reqs.any?

          git_commit_checker.head_commit_for_current_branch
        end

        def latest_version_for_git_dependency
          latest_git_version_details[:sha]
        end

        def fetch_latest_version_details
          return latest_git_version_details if git_dependency?
          return nil unless npm_details&.fetch("dist-tags", nil)

          dist_tag_version = version_from_dist_tags(npm_details)
          return { version: dist_tag_version } if dist_tag_version
          return nil if specified_dist_tag_requirement?

          { version: version_from_versions_array(npm_details) }
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_git_version_details
          semver_req =
            dependency.requirements.
            find { |req| req.dig(:source, :type) == "git" }&.
            fetch(:requirement)

          # If there was a semver requirement provided or the dependency was
          # pinned to a version, look for the latest tag
          if semver_req || git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return {
              sha: latest_tag&.fetch(:tag_sha) || dependency.version,
              version: latest_tag&.fetch(:tag)&.gsub(/^[^\d]*/, "")
            }
          end

          # Otherwise, if the gem isn't pinned, the latest version is just the
          # latest commit for the specified branch.
          unless git_commit_checker.pinned?
            return { sha: git_commit_checker.head_commit_for_current_branch }
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          { sha: dependency.version }
        end

        def updated_source
          # Never need to update source, unless a git_dependency
          return dependency_source_details unless git_dependency?

          # Update the git tag if updating a pinned version
          if git_commit_checker.pinned_ref_looks_like_version? &&
             !git_commit_checker.local_tag_for_latest_version.nil?
            new_tag = git_commit_checker.local_tag_for_latest_version
            return dependency_source_details.merge(ref: new_tag.fetch(:tag))
          end

          # Otherwise return the original source
          dependency_source_details
        end

        def dependency_source_details
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first
        end

        def version_from_dist_tags(npm_details)
          dist_tags = npm_details["dist-tags"].keys

          # Check if a dist tag was specified as a requirement. If it was, and
          # it exists, use it.
          dist_tag_req = dependency.requirements.find do |req|
            dist_tags.include?(req[:requirement])
          end&.fetch(:requirement)
          if dist_tag_req
            tag_vers = version_class.new(npm_details["dist-tags"][dist_tag_req])
            return tag_vers unless yanked?(tag_vers)
          end

          # Use the latest dist tag  unless there's a reason not to
          latest = version_class.new(npm_details["dist-tags"]["latest"])

          return if wants_prerelease? || latest.prerelease? || yanked?(latest)
          latest
        end

        def version_from_versions_array(npm_details)
          npm_details["versions"].
            keys.map { |v| version_class.new(v) }.
            reject { |v| v.prerelease? && !wants_prerelease? }.sort.reverse.
            find { |version| !yanked?(version) }
        end

        def yanked?(version)
          Excon.get(
            dependency_url + "/#{version}",
            headers: registry_auth_headers,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          ).status == 404
        end

        def npm_details
          @npm_details ||=
            begin
              npm_response = Excon.get(
                dependency_url,
                headers: registry_auth_headers,
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              )

              check_npm_response(npm_response)

              JSON.parse(npm_response.body)
            rescue JSON::ParserError
              @retry_count ||= 0
              @retry_count += 1
              if @retry_count > 2
                raise if dependency_registry == "registry.npmjs.org"
                return nil
              end
              sleep(rand(3.0..10.0)) && retry
            end
        end

        def check_npm_response(npm_response)
          if private_dependency_not_reachable?(npm_response)
            raise PrivateSourceNotReachable, dependency_registry
          end

          return if npm_response.status.to_s.start_with?("2")

          # Ignore 404s from the registry for libraries. These can be caused by
          # monorepos using Lerna that haven't pushed all of their packages, and
          # since no lockfile needs to be generated they won't cause problems
          # later.
          return if npm_response.status == 404 && library?
          raise "Got #{npm_response.status} response with body "\
                "#{npm_response.body}"
        end

        def private_dependency_not_reachable?(npm_response)
          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org" &&
             !dependency.name.start_with?("@")
            return false
          end

          [401, 403, 404].include?(npm_response.status)
        end

        def wants_prerelease?
          current_version = dependency.version
          if current_version && version_class.new(current_version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z]/)
          end
        end

        def specified_dist_tag_requirement?
          dependency.requirements.any? do |req|
            req[:requirement].match?(/^[A-Za-z]/)
          end
        end

        def library?
          dependency.version.nil?
        end

        def development_dependency?
          dependency.requirements.all? { |r| r[:groups] == ["devDependencies"] }
        end

        def dependency_url
          registry_url =
            if dependency_source_details.nil? then "https://registry.npmjs.org"
            else dependency_source_details.fetch(:url)
            end

          # npm registries expect slashes to be escaped
          escaped_dependency_name = dependency.name.gsub("/", "%2F")
          "#{registry_url}/#{escaped_dependency_name}"
        end

        def dependency_registry
          source = dependency_source_details

          if source.nil? then "registry.npmjs.org"
          else source.fetch(:url).gsub("https://", "").gsub("http://", "")
          end
        end

        def registry_auth_headers
          return {} unless auth_token
          { "Authorization" => "Bearer #{auth_token}" }
        end

        def auth_token
          env_token =
            credentials.
            find { |cred| cred["registry"] == dependency_registry }&.
            fetch("token")

          return env_token if env_token
          return unless npmrc

          auth_token_regex = %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}
          matches = []
          npmrc.content.scan(auth_token_regex) { matches << Regexp.last_match }

          npmrc_token =
            matches.find { |match| match[:registry] == dependency_registry }&.
            [](:token)

          return if npmrc_token.nil? || npmrc_token.start_with?("${")
          npmrc_token
        end

        def npmrc
          @npmrc ||= dependency_files.find { |f| f.name == ".npmrc" }
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
