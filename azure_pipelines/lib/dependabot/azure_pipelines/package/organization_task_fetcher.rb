# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/errors"

require "dependabot/azure_pipelines/package/azure_devops_http"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/resource_area_client"
require "dependabot/azure_pipelines/package/task_definition"
require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    module Package
      # Lists every version of every task installed in an Azure DevOps organization,
      # through `_apis/distributedtask/tasks`. This sees what the organization can
      # actually run, including tasks installed from Marketplace or private extensions.
      class OrganizationTaskFetcher
        extend T::Sig

        JsonValue = T.type_alias do
          T.nilable(
            T.any(
              String,
              Integer,
              Float,
              T::Boolean,
              T::Array[T.anything],
              T::Hash[String, T.anything]
            )
          )
        end
        TaskJson = T.type_alias { T::Hash[String, JsonValue] }
        API_VERSION = T.let("7.1", String)

        # The listing is the same for every dependency in a job, so it is fetched once
        # per organization.
        @tasks_cache = T.let(nil, T.nilable(T::Hash[String, T::Array[TaskDefinition]]))

        class << self
          extend T::Sig

          sig { returns(T::Hash[String, T::Array[TaskDefinition]]) }
          def tasks_cache
            @tasks_cache ||= {}
          end

          sig { void }
          def clear_cache!
            @tasks_cache = nil
            ResourceAreaClient.clear_cache!
          end
        end

        sig { params(organization: AzureDevOpsOrganization).void }
        def initialize(organization:)
          @organization = T.let(organization, AzureDevOpsOrganization)
        end

        sig { returns(T::Array[TaskDefinition]) }
        def tasks
          self.class.tasks_cache[@organization.url] ||= fetch_tasks
        end

        private

        sig { returns(T::Array[TaskDefinition]) }
        def fetch_tasks
          tasks_url = ResourceAreaClient.new(organization: @organization).distributed_tasks_url
          url = "#{tasks_url}_apis/distributedtask/tasks?allversions=true&api-version=#{API_VERSION}"
          response = AzureDevOpsHttp.get(url: url, headers: @organization.headers)

          # Even with sign-in redirects suppressed, older servers can still answer a
          # missing or invalid token with a sign-in page: a 203 or a redirect, with an
          # HTML body. Treating that as "no tasks" would hide a broken credential, so
          # every way of being turned away is reported as an authentication failure.
          raise Dependabot::PrivateSourceAuthenticationFailure, @organization.url if auth_failure?(response)

          unless response.status == 200
            raise Dependabot::DependabotError,
                  "Could not list the tasks installed in #{@organization.url} " \
                  "(#{AzureDevOpsHttp.describe_failure(response)})"
          end

          parse_tasks(response.body)
        end

        sig { params(response: Excon::Response).returns(T::Boolean) }
        def auth_failure?(response)
          return true if [203, 401, 403].include?(response.status)
          return true if (300..399).cover?(response.status)

          content_type = (response.headers["Content-Type"] || response.headers["content-type"]).to_s
          html_body = response.body.to_s.lstrip.match?(/\A(?:<!doctype\s+html|<html)\b/i)
          response.status == 200 && (content_type.include?("text/html") || html_body)
        end

        sig { params(body: T.nilable(String)).returns(T::Array[TaskDefinition]) }
        def parse_tasks(body)
          parsed = T.cast(JSON.parse(body.to_s), TaskJson)
          values = parsed["value"]
          unless values.is_a?(Array)
            raise Dependabot::DependabotError, "Unexpected task listing from #{@organization.url}"
          end

          task_values = T.let(values, T::Array[TaskJson])
          task_values.filter_map { |task| build_task(task) }
        rescue JSON::ParserError
          raise Dependabot::DependabotError, "Could not parse the task listing from #{@organization.url}"
        rescue TypeError
          raise Dependabot::DependabotError, "Unexpected task listing from #{@organization.url}"
        end

        sig { params(task: TaskJson).returns(T.nilable(TaskDefinition)) }
        def build_task(task)
          name = task["name"]
          version = task["version"]
          unless name.is_a?(String) && version.is_a?(Hash)
            raise Dependabot::DependabotError, "Task entry from #{@organization.url} is missing its name or version"
          end
          # Test versions are uploaded with `tfx build tasks upload` for trying a task
          # out, and are never something to move a pipeline onto.
          return nil if version["isTest"] == true

          version_data = T.cast(version, TaskJson)
          major = version_data["major"]
          minor = version_data.fetch("minor", 0)
          patch = version_data.fetch("patch", 0)
          unless major.is_a?(Integer) && minor.is_a?(Integer) && patch.is_a?(Integer)
            raise Dependabot::DependabotError, "Task version from #{@organization.url} is malformed"
          end

          TaskDefinition.new(
            name: name,
            version: Version.new([major, minor, patch].join(".")),
            id: string_or_nil(task["id"]),
            deprecated: task["deprecated"] == true,
            contribution_identifier: string_or_nil(task["contributionIdentifier"]),
            contribution_version: string_or_nil(task["contributionVersion"])
          )
        end

        sig { params(value: JsonValue).returns(T.nilable(String)) }
        def string_or_nil(value)
          value.is_a?(String) && !value.empty? ? value : nil
        end
      end
    end
  end
end
