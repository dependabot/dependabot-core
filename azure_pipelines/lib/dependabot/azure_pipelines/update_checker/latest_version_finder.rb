# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/registry_client"
require "dependabot/update_checkers/base"

require "dependabot/azure_pipelines/version"
require "dependabot/azure_pipelines/requirement"

module Dependabot
  module AzurePipelines
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder
        extend T::Sig

        AZURE_PIPELINES_TASK_LIST_API = "https://dev.azure.com/%<org_name>s/_apis/distributedtask/tasks?api-version=7.2-preview.1"
        AZURE_PIPELINES_TASK_DETAILS_API = "https://dev.azure.com/%<org_name>s/_apis/distributedtask/tasks/%<task_id>s?allversions=true&api-version=7.2-preview.1"

        sig do
          params(
            dependency: Dependabot::Dependency,
            ignored_versions: T::Array[String],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependency:, ignored_versions:, credentials:)
          @dependency = dependency
          @ignored_versions = ignored_versions
          @credentials = credentials
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(Dependabot::Version)
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_latest_version
          versions = available_versions
          versions = filter_ignored_versions(versions)
          versions.max
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def available_versions
          tasks.map { |v| version_class.new(v) }
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_ignored_versions(versions)
          return versions if ignored_versions.empty?

          versions.reject do |version|
            ignore_requirements.any? { |r| r.satisfied_by?(version) }
          end
        end

        sig { returns(T::Array[String]) }
        def tasks
          response = tasks_response
          return [] unless response.status == 200

          tasks_data = JSON.parse(response.body)["value"]
          task = tasks_data.first { |t| t["name"] == dependency.name || t["id"] == dependency.name }

          task ? task_details(task["id"]) : []
        end

        sig { params(task_id: String).returns(T::Array[String]) }
        def task_details(task_id)
          response = task_details_response(task_id)
          return [] unless response.status == 200

          task_data = JSON.parse(response.body)
          task_data["value"].map do |task|
            task["version"]["major"].to_s + "." + task["version"]["minor"].to_s + "." + task["version"]["patch"].to_s
          end
        end

        sig { returns(Excon::Response) }
        def tasks_response
          # TODO: Get the org_name from credentials or configuration
          url = format(AZURE_PIPELINES_TASK_LIST_API, { org_name: "contoso" })

          # TODO: Authenticate using credentials
          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => "application/json" }
          )
        end

        sig { params(task_id: String).returns(Excon::Response) }
        def task_details_response(task_id)
          # TODO: Get the org_name from credentials or configuration
          url = format(AZURE_PIPELINES_TASK_DETAILS_API, { org_name: "contoso", task_id: task_id })

          # TODO: Authenticate using credentials
          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => "application/json" }
          )
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end
      end
    end
  end
end
