# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/version"
require "excon"
require "json"

module Dependabot
  module Bazel
    class UpdateChecker
      # Handles WORKSPACE dependency updates (http_archive, git_repository)
      class WorkspaceVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
          ).void
        end
        def initialize(dependency:, dependency_files:, ignored_versions:,
                      raise_on_ignored: )
          @dependency = dependency
          @dependency_files = dependency_files
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(
            begin
              versions = fetch_versions
              return nil if versions.empty?

              candidate_versions = filter_versions(versions)
              candidate_versions.max_by(&:to_s)
            end,
            T.nilable(Dependabot::Version)
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return @dependency.requirements unless can_update?

          latest = latest_version
          return @dependency.requirements unless latest

          declaration = dependency_declaration
          return @dependency.requirements if declaration.empty?

          # Update the requirement for the WORKSPACE file
          @dependency.requirements.map do |req|
            if req[:file] == declaration[:file]
              case declaration[:type]
              when :http_archive
                update_http_archive_requirement(req, latest)
              when :git_repository
                update_git_repository_requirement(req, latest)
              else
                req
              end
            else
              req
            end
          end
        end
        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_security_fix_version
          nil
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def versions
          @versions ||= T.let(fetch_versions, T.nilable(T::Array[Dependabot::Version]))
        end

        sig { returns(T::Boolean) }
        def can_update?
          !latest_version.nil?
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_files
          @workspace_files ||= T.let(
            @dependency_files.select { |f| f.name.match?(/WORKSPACE(\.bazel)?$/) },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def fetch_versions
          declaration = dependency_declaration
          return [] if declaration.empty?

          case declaration[:type]
          when :http_archive
            fetch_http_archive_versions(declaration)
          when :git_repository
            fetch_git_repository_versions(declaration)
          else
            []
          end
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_versions(versions)
          filtered = versions.reject do |version|
            @ignored_versions.include?(version.to_s) ||
              ignore_reqs.any? { |req| req.satisfied_by?(version) }
          end

          # Filter out pre-releases unless current version is a pre-release
          unless current_version_is_prerelease?
            filtered = filtered.reject(&:prerelease?)
          end

          filtered
        end

        sig { returns(T::Boolean) }
        def current_version_is_prerelease?
          return false unless @dependency.version

          version = Dependabot::Bazel::Version.new(@dependency.version)
          version.prerelease?
        rescue ArgumentError
          false
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_reqs
          @ignore_reqs ||= T.let(
            @ignored_versions.filter_map do |req|
              Dependabot::Bazel::Requirement.new(req) if req.match?(/^[<>=~]/)
            rescue Gem::Requirement::BadRequirementError
              nil
            end,
            T.nilable(T::Array[Dependabot::Requirement])
          )
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def dependency_declaration
          @dependency_declaration ||= T.let(
            begin
              declaration = {}
              workspace_files.each do |file|
                content = file.content
                next unless content

                # Check for http_archive with this dependency name
                http_archive_match = content.match(
                  /http_archive\(\s*name\s*=\s*"#{Regexp.escape(@dependency.name)}"[^)]*\)/m
                )
                if http_archive_match
                  declaration[:type] = :http_archive
                  declaration[:file] = file.name
                  declaration[:declaration] = http_archive_match[0]
                  declaration_text = T.must(http_archive_match[0])
                  declaration[:attributes] = parse_http_archive_attributes(declaration_text)
                  break
                end

                # Check for git_repository with this dependency name
                git_repo_match = content.match(
                  /git_repository\(\s*name\s*=\s*"#{Regexp.escape(@dependency.name)}"[^)]*\)/m
                )
                if git_repo_match
                  declaration[:type] = :git_repository
                  declaration[:file] = file.name
                  declaration[:declaration] = git_repo_match[0]
                  declaration_text = T.must(git_repo_match[0])
                  declaration[:attributes] = parse_git_repository_attributes(declaration_text)
                  break
                end
              end
              declaration
            end,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        sig { params(declaration_text: String).returns(T::Hash[Symbol, T.untyped]) }
        def parse_http_archive_attributes(declaration_text)
          attributes = {}

          # Extract name
          name_match = declaration_text.match(/name\s*=\s*"([^"]+)"/)
          attributes[:name] = name_match[1] if name_match

          # Extract URLs
          urls_match = declaration_text.match(/urls?\s*=\s*\[([^\]]+)\]/)
          if urls_match
            urls_content = T.must(urls_match[1])
            attributes[:urls] = urls_content.scan(/"([^"]+)"/).flatten
          end

          # Extract strip_prefix
          strip_prefix_match = declaration_text.match(/strip_prefix\s*=\s*"([^"]+)"/)
          attributes[:strip_prefix] = strip_prefix_match[1] if strip_prefix_match

          # Extract sha256
          sha256_match = declaration_text.match(/sha256\s*=\s*"([^"]+)"/)
          attributes[:sha256] = sha256_match[1] if sha256_match

          # Extract type
          type_match = declaration_text.match(/type\s*=\s*"([^"]+)"/)
          attributes[:type] = type_match[1] if type_match

          attributes
        end

        sig { params(declaration_text: String).returns(T::Hash[Symbol, T.untyped]) }
        def parse_git_repository_attributes(declaration_text)
          attributes = {}

          # Extract name
          name_match = declaration_text.match(/name\s*=\s*"([^"]+)"/)
          attributes[:name] = name_match[1] if name_match

          # Extract remote URL
          remote_match = declaration_text.match(/remote\s*=\s*"([^"]+)"/)
          attributes[:remote] = remote_match[1] if remote_match

          # Extract commit
          commit_match = declaration_text.match(/commit\s*=\s*"([^"]+)"/)
          attributes[:commit] = commit_match[1] if commit_match

          # Extract tag
          tag_match = declaration_text.match(/tag\s*=\s*"([^"]+)"/)
          attributes[:tag] = tag_match[1] if tag_match

          # Extract shallow_since
          shallow_since_match = declaration_text.match(/shallow_since\s*=\s*"([^"]+)"/)
          attributes[:shallow_since] = shallow_since_match[1] if shallow_since_match

          attributes
        end

        sig { params(declaration: T::Hash[Symbol, T.untyped]).returns(T::Array[Dependabot::Version]) }
        def fetch_http_archive_versions(declaration)
          attrs = declaration[:attributes] || {}
          urls = attrs[:urls] || []

          versions = []
          urls.each do |url|
            versions.concat(fetch_versions_from_github_releases(url))
          end

          versions.uniq.compact
        end

        sig { params(declaration: T::Hash[Symbol, T.untyped]).returns(T::Array[Dependabot::Version]) }
        def fetch_git_repository_versions(declaration)
          attrs = declaration[:attributes] || {}
          remote_url = attrs[:remote]
          return [] unless remote_url

          fetch_versions_from_git_tags(remote_url)
        end

        sig { params(url: String).returns(T::Array[Dependabot::Version]) }
        def fetch_versions_from_github_releases(url)
          # Extract GitHub repo from archive URL patterns
          github_repo = extract_github_repo_from_url(url)
          return [] unless github_repo

          fetch_github_releases(github_repo)
        end

        sig { params(remote_url: String).returns(T::Array[Dependabot::Version]) }
        def fetch_versions_from_git_tags(remote_url)
          # Extract GitHub repo from git URL
          github_repo = extract_github_repo_from_git_url(remote_url)
          return [] unless github_repo

          fetch_github_tags(github_repo)
        end

        sig { params(url: String).returns(T.nilable(String)) }
        def extract_github_repo_from_url(url)
          # Match patterns like:
          # https://github.com/owner/repo/archive/v1.2.3.tar.gz
          # https://github.com/owner/repo/archive/refs/tags/v1.2.3.tar.gz
          match = url.match(%r{github\.com/([^/]+/[^/]+)/archive/})
          match&.[](1)
        end

        sig { params(remote_url: String).returns(T.nilable(String)) }
        def extract_github_repo_from_git_url(remote_url)
          # Match patterns like:
          # https://github.com/owner/repo.git
          # git@github.com:owner/repo.git
          match = remote_url.match(%r{github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$})
          match&.[](1)
        end

        sig { params(repo: String).returns(T::Array[Dependabot::Version]) }
        def fetch_github_releases(repo)
          return [] unless github_token

          begin
            response = Excon.get(
              "https://api.github.com/repos/#{repo}/releases",
              headers: {
                "Authorization" => "token #{github_token}",
                "Accept" => "application/vnd.github.v3+json",
                "User-Agent" => "Dependabot Core"
              },
              middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
            )

            return [] unless response.status == 200

            releases = JSON.parse(response.body)
            releases.filter_map do |release|
              next if release["draft"] || release["prerelease"]

              tag_name = release["tag_name"]
              next unless tag_name

              version_string = normalize_version_string(tag_name)
              Dependabot::Bazel::Version.new(version_string)
            rescue ArgumentError
              nil
            end
          rescue Excon::Error, JSON::ParserError => e
            Dependabot.logger.warn("Failed to fetch GitHub releases for #{repo}: #{e.message}")
            []
          end
        end

        sig { params(repo: String).returns(T::Array[Dependabot::Version]) }
        def fetch_github_tags(repo)
          return [] unless github_token

          begin
            response = Excon.get(
              "https://api.github.com/repos/#{repo}/git/refs/tags",
              headers: {
                "Authorization" => "token #{github_token}",
                "Accept" => "application/vnd.github.v3+json",
                "User-Agent" => "Dependabot Core"
              },
              middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
            )

            return [] unless response.status == 200

            tags = JSON.parse(response.body)
            tags.filter_map do |tag|
              ref = tag["ref"]
              next unless ref && ref.start_with?("refs/tags/")

              tag_name = ref.sub("refs/tags/", "")
              version_string = normalize_version_string(tag_name)
              Dependabot::Bazel::Version.new(version_string)
            rescue ArgumentError
              nil
            end
          rescue Excon::Error, JSON::ParserError => e
            Dependabot.logger.warn("Failed to fetch GitHub tags for #{repo}: #{e.message}")
            []
          end
        end

        sig { params(requirement: T::Hash[Symbol, T.untyped], new_version: Dependabot::Version).returns(T::Hash[Symbol, T.untyped]) }
        def update_http_archive_requirement(requirement, new_version)
          declaration = dependency_declaration
          attrs = declaration[:attributes] || {}
          original_urls = attrs[:urls] || []

          # Update URLs to use the new version
          updated_urls = original_urls.map do |url|
            update_url_version(url, new_version.to_s)
          end

          # Create updated requirement metadata
          requirement.merge(
            requirement: new_version.to_s,
            metadata: {
              urls: updated_urls,
              strip_prefix: attrs[:strip_prefix] ? update_strip_prefix_version(attrs[:strip_prefix], new_version.to_s) : nil,
              type: attrs[:type]
            }.compact
          )
        end

        sig { params(requirement: T::Hash[Symbol, T.untyped], new_version: Dependabot::Version).returns(T::Hash[Symbol, T.untyped]) }
        def update_git_repository_requirement(requirement, new_version)
          declaration = dependency_declaration
          attrs = declaration[:attributes] || {}

          # Create updated requirement metadata
          requirement.merge(
            requirement: new_version.to_s,
            metadata: {
              remote: attrs[:remote],
              tag: "v#{new_version}",
              shallow_since: attrs[:shallow_since] # Note: This should be updated by file updater
            }.compact
          )
        end

        sig { params(tag_name: String).returns(String) }
        def normalize_version_string(tag_name)
          # Remove common prefixes like 'v', 'release-', etc.
          tag_name.sub(/^(v|version|release-?)/i, "")
        end

        sig { returns(T.nilable(String)) }
        def github_token
          # TODO: Access GitHub token from credentials
          # This would come from the Dependabot credentials system
          ENV["GITHUB_TOKEN"] || ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
        end

        sig { returns(String) }
        def updated_declaration_text
          return "" unless can_update?

          latest = latest_version
          return "" unless latest

          declaration = dependency_declaration
          return "" if declaration.empty?

          case declaration[:type]
          when :http_archive
            update_http_archive_declaration(declaration, latest)
          when :git_repository
            update_git_repository_declaration(declaration, latest)
          else
            ""
          end
        end

        sig { params(declaration: T::Hash[Symbol, T.untyped], new_version: Dependabot::Version).returns(String) }
        def update_http_archive_declaration(declaration, new_version)
          attrs = declaration[:attributes] || {}
          original_urls = attrs[:urls] || []

          # Update URLs to use the new version
          updated_urls = original_urls.map do |url|
            update_url_version(url, new_version.to_s)
          end

          # Build updated declaration
          parts = ["name = \"#{attrs[:name]}\""]

          if updated_urls.size == 1
            parts << "url = \"#{updated_urls.first}\""
          else
            url_list = updated_urls.map { |url| "\"#{url}\"" }.join(", ")
            parts << "urls = [#{url_list}]"
          end

          # Note: SHA256 would need to be calculated for the new archive
          # This is typically done by the file updater component
          if attrs[:strip_prefix]
            updated_strip_prefix = update_strip_prefix_version(attrs[:strip_prefix], new_version.to_s)
            parts << "strip_prefix = \"#{updated_strip_prefix}\""
          end

          if attrs[:type]
            parts << "type = \"#{attrs[:type]}\""
          end

          "http_archive(#{parts.join(', ')})"
        end

        sig { params(declaration: T::Hash[Symbol, T.untyped], new_version: Dependabot::Version).returns(String) }
        def update_git_repository_declaration(declaration, new_version)
          attrs = declaration[:attributes] || {}

          parts = ["name = \"#{attrs[:name]}\""]
          parts << "remote = \"#{attrs[:remote]}\"" if attrs[:remote]

          # Update tag instead of commit for version-based updates
          parts << "tag = \"v#{new_version}\""

          if attrs[:shallow_since]
            # Note: shallow_since would need to be updated to match the new tag's commit date
            # This is typically done by the file updater component
            parts << "shallow_since = \"#{attrs[:shallow_since]}\""
          end

          "git_repository(#{parts.join(', ')})"
        end

        sig { params(url: String, new_version: String).returns(String) }
        def update_url_version(url, new_version)
          # Replace version patterns in GitHub archive URLs
          url.gsub(%r{/archive/(?:refs/tags/)?v?[\d.]+(?:-[^/]*)?\.}, "/archive/refs/tags/v#{new_version}.")
        end

        sig { params(strip_prefix: String, new_version: String).returns(String) }
        def update_strip_prefix_version(strip_prefix, new_version)
          # Update version in strip_prefix (e.g., "repo-1.2.3" -> "repo-1.2.4")
          strip_prefix.gsub(/[\d.]+(?:-[^\/]*)?$/, new_version)
        end

        sig { returns(T::Boolean) }
        def supports_version_constraints?
          # WORKSPACE dependencies don't typically support version ranges
          # Each dependency specifies an exact version/commit/tag
          false
        end
      end
    end
  end
end
