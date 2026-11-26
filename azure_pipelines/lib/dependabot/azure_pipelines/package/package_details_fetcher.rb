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
require "dependabot/package/release_cooldown_options"
require "dependabot/registry_client"
require "dependabot/update_checkers/cooldown_calculation"

require "dependabot/azure_pipelines/constants"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/installed_extensions_client"
require "dependabot/azure_pipelines/package/marketplace_client"
require "dependabot/azure_pipelines/package/organization_task_fetcher"
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
      #
      # When a credential for an Azure DevOps organization is configured, the tasks
      # that organization has installed are used instead, and the tasks repository is
      # only consulted to date the tasks Microsoft ships. That covers tasks installed
      # from Marketplace or private extensions, and tasks referenced by GUID.
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
            OrganizationTaskFetcher.clear_cache!
            MarketplaceClient.clear_cache!
            InstalledExtensionsClient.clear_cache!
          end
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            fetch_release_dates: T::Boolean,
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(dependency:, credentials:, fetch_release_dates: false, cooldown_options: nil)
          @dependency = dependency
          @credentials = credentials
          @fetch_release_dates = fetch_release_dates
          @cooldown_options = cooldown_options
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
        # request metadata at something more specific than the repository root. Tasks
        # an organization installed from an extension have no such directory.
        sig { returns(T.nilable(String)) }
        def task_directory
          definitions = task_directory_definitions
          current = dependency.version
          matching =
            if current && Version.correct?(current)
              major = Version.new(current).truncate(1).to_s
              definitions.find { |task| task.version.truncate(1).to_s == major }
            end

          (matching || definitions.first)&.directory
        end

        sig { returns(T::Array[TaskDefinition]) }
        def task_directory_definitions
          return [] if organization && task_definitions.any?(&:contribution_identifier)

          name = organization ? task_definitions.first&.name : dependency.name
          github_task_definitions(name)
        end

        private

        sig { returns(T::Boolean) }
        def fetch_release_dates?
          @fetch_release_dates
        end

        sig { returns(T.nilable(AzureDevOpsOrganization)) }
        def organization
          return @organization if defined?(@organization)

          @organization = T.let(
            AzureDevOpsOrganization.from_credentials(credentials),
            T.nilable(AzureDevOpsOrganization)
          )
        end

        # An organization lists every version of a task, so several can collapse onto
        # the same release once truncated to the pin's precision. The newest one
        # represents the release, and the earliest date stands for when that release
        # first became available.
        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          task_definitions
            .group_by { |task| task.version.truncate(precision) }
            .map do |_version, tasks|
              newest = T.must(tasks.max_by(&:version))
              build_release(newest, released_at: tasks.filter_map { |task| released_at(task) }.min)
            end
        end

        sig do
          params(task: TaskDefinition, released_at: T.nilable(Time))
            .returns(Dependabot::Package::PackageRelease)
        end
        def build_release(task, released_at:)
          Dependabot::Package::PackageRelease.new(
            version: task.version.truncate(precision),
            released_at: released_at,
            url: release_url(task),
            details: {
              "task_id" => task.id,
              "task_directory" => task.directory,
              "task_version" => task.version.to_s,
              "contribution_identifier" => task.contribution_identifier,
              "contribution_version" => task.contribution_version,
              "deprecated" => task.deprecated,
              "preview" => task.preview
            }
          )
        end

        sig { params(task: TaskDefinition).returns(T.nilable(String)) }
        def release_url(task)
          extension_id = task.extension_id
          return MarketplaceClient.item_url(extension_id) if extension_id

          directory = task.directory
          directory ? "#{TASKS_REPO_URL}/tree/#{ref}/#{TASKS_DIRECTORY}/#{directory}" : nil
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
            organization ? organization_task_definitions : github_task_definitions(dependency.name),
            T.nilable(T::Array[TaskDefinition])
          )
        end

        # A step can name a task by its name, its GUID, or its name qualified by the
        # contribution that installed it. When a bare name matches tasks from more
        # than one source, Azure DevOps refuses to run the step, so nothing is
        # proposed rather than guessing which one was meant.
        sig { returns(T::Array[TaskDefinition]) }
        def organization_task_definitions
          name = dependency.name
          tasks = OrganizationTaskFetcher.new(organization: T.must(organization)).tasks.select do |task|
            task.id&.casecmp?(name) ||
              task.name.casecmp?(name) ||
              "#{task.contribution_identifier}.#{task.name}".casecmp?(name)
          end

          if tasks.map { |task| task_identity(task) }.uniq.length > 1
            Dependabot.logger.info("#{name} matches more than one task installed in #{T.must(organization).url}")
            return []
          end

          tasks
        end

        sig { params(task: TaskDefinition).returns(String) }
        def task_identity(task)
          id = task.id
          return "id:#{id.downcase}" if id

          contribution = task.contribution_identifier
          return "contribution:#{contribution.downcase}:#{task.name.downcase}" if contribution

          "name:#{task.name.downcase}"
        end

        sig { params(name: T.nilable(String)).returns(T::Array[TaskDefinition]) }
        def github_task_definitions(name)
          return [] unless name

          @github_task_definitions ||= T.let({}, T.nilable(T::Hash[String, T::Array[TaskDefinition]]))
          @github_task_definitions[name.downcase] ||=
            candidate_directories(name).filter_map { |directory| fetch_task_definition(directory, name) }
        end

        # Narrow 200-odd directories down to the handful that could hold this task. A
        # task referenced by GUID has no matching directory name and resolves to
        # nothing, which leaves the pipeline untouched.
        sig { params(name: String).returns(T::Array[String]) }
        def candidate_directories(name)
          pattern = /\A#{Regexp.escape(name)}V\d+\z/i
          task_directories.select { |directory| directory.match?(pattern) }.sort
        end

        sig { params(directory: String, expected_name: String).returns(T.nilable(TaskDefinition)) }
        def fetch_task_definition(directory, expected_name)
          parsed = fetch_json("#{TASKS_RAW_URL}/#{ref}/#{TASKS_DIRECTORY}/#{directory}/task.json")
          return nil unless parsed.is_a?(Hash)

          name = parsed["name"]
          return nil unless name.is_a?(String) && name.casecmp?(expected_name)

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
            deprecated: parsed["deprecated"] == true,
            preview: parsed["preview"] == true
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

          # A task installed from an extension shipped with the extension version that
          # contributed it, which the Marketplace dates.
          extension_id = task.extension_id
          contribution_version = task.contribution_version
          if extension_id && contribution_version
            installed_date = installed_before_cooldown(extension_id)
            return installed_date if installed_date

            marketplace_date = marketplace.published_at(extension_id, contribution_version)
            return marketplace_date if marketplace_date
          end

          git_based_release_date(task)
        end

        # When an extension was installed before the longest configured cooldown began,
        # every task version it contributes was released earlier still, so none of them
        # can be in cooldown and the Marketplace need not be asked. The install time is
        # later than the real release date, which makes it a safe stand-in: it can only
        # make a release look newer than it is, never old enough to skip a cooldown.
        sig { params(extension_id: String).returns(T.nilable(Time)) }
        def installed_before_cooldown(extension_id)
          days = longest_cooldown_days
          return nil unless days

          installed_at = installed_extensions.installed_at(extension_id)
          return nil unless installed_at
          return nil if Dependabot::UpdateCheckers::CooldownCalculation.within_cooldown_window?(installed_at, days)

          installed_at
        end

        sig { returns(T.nilable(Integer)) }
        def longest_cooldown_days
          cooldown = @cooldown_options
          return nil unless cooldown

          [
            cooldown.default_days,
            cooldown.semver_major_days,
            cooldown.semver_minor_days,
            cooldown.semver_patch_days
          ].max
        end

        sig { returns(InstalledExtensionsClient) }
        def installed_extensions
          @installed_extensions ||= T.let(
            InstalledExtensionsClient.new(organization: T.must(organization)),
            T.nilable(InstalledExtensionsClient)
          )
        end

        sig { params(task: TaskDefinition).returns(T.nilable(Time)) }
        def git_based_release_date(task)
          # A pipeline pinned to a major moves between majors, so the date that matters
          # is when that major first shipped. A fully pinned version moves between
          # sprints, so the sprint release date is the right one.
          return release_dates["v#{task.version.segments[1]}"] unless precision == 1

          directory = task.directory || github_directory_for(task)
          directory ? first_seen_at(directory) : nil
        end

        sig { returns(MarketplaceClient) }
        def marketplace
          @marketplace ||= T.let(
            MarketplaceClient.new(organization: T.must(organization)),
            T.nilable(MarketplaceClient)
          )
        end

        # The tasks repository directory of a task Microsoft ships that was found
        # through an organization, matched on major version and, where both sides
        # declare one, the task's GUID.
        sig { params(task: TaskDefinition).returns(T.nilable(String)) }
        def github_directory_for(task)
          major = task.version.truncate(1)
          task_id = task.id
          github_task_definitions(task.name).find do |definition|
            definition_id = definition.id
            definition.version.truncate(1) == major &&
              definition_id && task_id && definition_id.casecmp?(task_id) == true
          end&.directory
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
