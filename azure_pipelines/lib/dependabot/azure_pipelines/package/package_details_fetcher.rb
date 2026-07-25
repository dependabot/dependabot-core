# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "time"

require "dependabot/credential"
require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/logger"
require "dependabot/package/package_details"
require "dependabot/package/package_release"
require "dependabot/registry_client"

require "dependabot/azure_pipelines/constants"
require "dependabot/azure_pipelines/package/task_definition"
require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    module Package
      # Resolves the versions of an Azure Pipelines task from the repository Microsoft
      # develops its tasks in.
      #
      # Every major version of a task is a separate directory under `Tasks/`, named
      # `<Name>V<major>`, holding a `task.json` that declares the task's GUID, the name
      # pipelines refer to it by, and its full version. Lookups therefore narrow on the
      # directory name and confirm on `task.json`, because the two do not always agree:
      # `ANTV1` declares `"name": "Ant"`.
      #
      # Versions resolve at the latest published release rather than the default
      # branch. Releases lag the branch, which is the point: Azure DevOps rolls tasks
      # out over sprints, so a released tag is closer to what organizations can
      # actually run.
      class PackageDetailsFetcher
        extend T::Sig

        # The task listing, the releases and the resolved ref are the same for every
        # dependency in a job, so they are looked up once per process.
        @task_directories_cache = T.let(nil, T.nilable(T::Hash[String, T::Array[String]]))
        @release_dates_cache = T.let(nil, T.nilable(T::Hash[String, Time]))
        @latest_ref_cache = T.let(nil, T.nilable(String))

        class << self
          extend T::Sig

          sig { returns(T.nilable(T::Hash[String, Time])) }
          attr_accessor :release_dates_cache

          sig { returns(T.nilable(String)) }
          attr_accessor :latest_ref_cache

          sig { returns(T::Hash[String, T::Array[String]]) }
          def task_directories_cache
            @task_directories_cache ||= {}
          end

          sig { void }
          def clear_cache!
            @task_directories_cache = nil
            @release_dates_cache = nil
            @latest_ref_cache = nil
          end
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            fetch_release_dates: T::Boolean
          ).void
        end
        def initialize(dependency:, credentials:, fetch_release_dates: false)
          @dependency = dependency
          @credentials = credentials
          @fetch_release_dates = fetch_release_dates
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          Dependabot::Package::PackageDetails.new(dependency: dependency, releases: releases)
        end

        # The directory holding the task's current major version, used to point pull
        # request metadata at something more specific than the repository root.
        sig { returns(T.nilable(String)) }
        def task_directory
          current = dependency.version
          matching =
            if current && Version.correct?(current)
              major = Version.new(current).truncate(1).to_s
              task_definitions.find { |task| task.version.truncate(1).to_s == major }
            end

          (matching || task_definitions.first)&.directory
        end

        private

        sig { returns(T::Boolean) }
        def fetch_release_dates?
          @fetch_release_dates
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          task_definitions.map { |task| build_release(task) }
        end

        sig { params(task: TaskDefinition).returns(Dependabot::Package::PackageRelease) }
        def build_release(task)
          Dependabot::Package::PackageRelease.new(
            version: task.version.truncate(precision),
            released_at: released_at(task),
            url: "#{TASKS_REPO_URL}/tree/#{ref}/#{TASKS_DIRECTORY}/#{task.directory}",
            details: {
              "task_id" => task.id,
              "task_directory" => task.directory,
              "task_version" => task.version.to_s,
              "deprecated" => task.deprecated
            }
          )
        end

        # How precisely the pipeline pins this task. Candidates are compared and
        # rendered at the same precision, so a pipeline pinned to `Maven@4` is only
        # offered a new major and never a same-major no-op.
        #
        # Files can disagree about precision, and merging them leaves one dependency
        # carrying all of it. Resolving at the finest precision anyone asked for lets
        # each requirement be rendered back at its own.
        sig { returns(Integer) }
        def precision
          @precision ||= T.let(
            begin
              pinned = dependency.requirements.map { |requirement| requirement[:requirement] }
              pinned << dependency.version

              pinned.filter_map do |pin|
                Version.new(pin).precision if pin.is_a?(String) && Version.correct?(pin)
              end.max || 1
            end,
            T.nilable(Integer)
          )
        end

        sig { returns(T::Array[TaskDefinition]) }
        def task_definitions
          @task_definitions ||= T.let(
            candidate_directories.filter_map { |directory| fetch_task_definition(directory) },
            T.nilable(T::Array[TaskDefinition])
          )
        end

        # Narrow 200-odd directories down to the handful that could hold this task. A
        # task referenced by GUID has no matching directory name and resolves to
        # nothing, which leaves the pipeline untouched.
        sig { returns(T::Array[String]) }
        def candidate_directories
          pattern = /\A#{Regexp.escape(dependency.name)}V\d+\z/i
          task_directories.select { |directory| directory.match?(pattern) }.sort
        end

        sig { params(directory: String).returns(T.nilable(TaskDefinition)) }
        def fetch_task_definition(directory)
          parsed = fetch_json("#{TASKS_RAW_URL}/#{ref}/#{TASKS_DIRECTORY}/#{directory}/task.json")
          return nil unless parsed.is_a?(Hash)

          name = parsed["name"]
          return nil unless name.is_a?(String) && name.casecmp?(dependency.name)

          version = parsed["version"]
          return nil unless version.is_a?(Hash)

          major = version["Major"]
          return nil unless major.is_a?(Integer)

          id = parsed["id"]

          TaskDefinition.new(
            directory: directory,
            name: name,
            version: Version.new([major, version["Minor"].to_i, version["Patch"].to_i].join(".")),
            id: id.is_a?(String) ? id : nil,
            deprecated: parsed["deprecated"] == true
          )
        end

        sig { returns(T::Array[String]) }
        def task_directories
          self.class.task_directories_cache[ref] ||= fetch_task_directories
        end

        # The git trees API returns every entry under `Tasks/` in a single response,
        # which the contents API would spread over several pages.
        sig { returns(T::Array[String]) }
        def fetch_task_directories
          parsed = fetch_json("#{TASKS_API_URL}/git/trees/#{ref}:#{TASKS_DIRECTORY}")
          return [] unless parsed.is_a?(Hash)

          tree = parsed["tree"]
          return [] unless tree.is_a?(Array)

          tree.filter_map { |entry| entry["path"] if entry.is_a?(Hash) && entry["type"] == "tree" }
        end

        sig { returns(String) }
        def ref
          self.class.latest_ref_cache ||= fetch_latest_ref
        end

        sig { returns(String) }
        def fetch_latest_ref
          response = get("#{TASKS_API_URL}/releases/latest")

          # Having published no release at all is the one case where the default branch
          # is the right answer. Treating a rate limit or a server error the same way
          # would quietly resolve versions Azure DevOps has not rolled out yet, which is
          # the whole reason for pinning to a release in the first place.
          return DEFAULT_REF if response.status == 404

          unless response.status == 200
            raise Dependabot::DependabotError,
                  "Got #{response.status} looking up the latest #{TASKS_REPO} release"
          end

          parsed = parse(response.body)
          tag = parsed.is_a?(Hash) ? parsed["tag_name"] : nil

          tag.is_a?(String) && !tag.empty? ? tag : DEFAULT_REF
        end

        sig { params(task: TaskDefinition).returns(T.nilable(Time)) }
        def released_at(task)
          # Release dates only feed cooldown, and establishing them costs extra
          # requests, so they are skipped unless a cooldown is configured.
          return nil unless fetch_release_dates?

          # A pipeline pinned to a major moves between majors, so the date that matters
          # is when that major first shipped. A fully pinned version moves between
          # sprints, so the sprint release date is the right one.
          return first_seen_at(task.directory) if precision == 1

          release_dates["v#{task.version.segments[1]}"]
        end

        # The oldest commit touching the major's `task.json`, which is when Microsoft
        # started shipping it. The commits API only exposes that through the last page
        # of the paginated result.
        sig { params(directory: String).returns(T.nilable(Time)) }
        def first_seen_at(directory)
          url = "#{TASKS_API_URL}/commits?path=#{TASKS_DIRECTORY}/#{directory}/task.json&per_page=1"

          response = get(url)
          return nil unless response.status == 200

          parsed = last_page_url(response) ? fetch_json(T.must(last_page_url(response))) : parse(response.body)
          return nil unless parsed.is_a?(Array)

          date = parsed.first&.dig("commit", "committer", "date")
          date.is_a?(String) ? Time.parse(date) : nil
        rescue ArgumentError
          nil
        end

        sig { returns(T::Hash[String, Time]) }
        def release_dates
          self.class.release_dates_cache ||= fetch_release_dates
        end

        sig { returns(T::Hash[String, Time]) }
        def fetch_release_dates
          parsed = fetch_json("#{TASKS_API_URL}/releases?per_page=100")
          return {} unless parsed.is_a?(Array)

          parsed.each_with_object({}) do |release, dates|
            next unless release.is_a?(Hash)

            tag = release["tag_name"]
            published = release["published_at"]
            next unless tag.is_a?(String) && published.is_a?(String)

            begin
              dates[tag] = Time.parse(published)
            rescue ArgumentError
              next
            end
          end
        end

        sig { params(response: Excon::Response).returns(T.nilable(String)) }
        def last_page_url(response)
          link = response.headers["Link"]
          return nil unless link.is_a?(String)

          link[/<([^>]+)>;\s*rel="last"/, 1]
        end

        sig { params(url: String).returns(T.nilable(Object)) }
        def fetch_json(url)
          response = get(url)
          return nil unless response.status == 200

          parse(response.body)
        end

        sig { params(body: T.nilable(Object)).returns(T.nilable(Object)) }
        def parse(body)
          JSON.parse(T.cast(body, String))
        rescue JSON::ParserError, TypeError => e
          Dependabot.logger.warn("Could not parse response from #{TASKS_REPO}: #{e.message}")
          nil
        end

        sig { params(url: String).returns(Excon::Response) }
        def get(url)
          Dependabot::RegistryClient.get(url: url, headers: headers)
        end

        sig { returns(T::Hash[String, String]) }
        def headers
          @headers ||= T.let(
            begin
              base = { "Accept" => "application/json", "User-Agent" => "dependabot-core" }
              token = github_token
              token ? base.merge("Authorization" => "token #{token}") : base
            end,
            T.nilable(T::Hash[String, String])
          )
        end

        sig { returns(T.nilable(String)) }
        def github_token
          credentials
            .select { |cred| cred["type"] == "git_source" && cred["host"] == "github.com" }
            .filter_map { |cred| cred["password"] }
            .first
        end
      end
    end
  end
end
