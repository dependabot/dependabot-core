# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    module Package
      # A single version of an Azure Pipelines task, either as declared by the
      # `task.json` in its directory of the tasks repository, or as reported by an
      # Azure DevOps organization.
      class TaskDefinition < T::Struct
        extend T::Sig

        const :directory, T.nilable(String), default: nil
        const :name, String
        const :version, Dependabot::AzurePipelines::Version
        const :id, T.nilable(String)
        const :deprecated, T::Boolean, default: false
        # Set for tasks an organization installed from an extension, as
        # `<publisher>.<extension>.<contribution>`, along with the extension version
        # that contributed this task version.
        const :contribution_identifier, T.nilable(String), default: nil
        const :contribution_version, T.nilable(String), default: nil

        sig { returns(T.nilable(String)) }
        def extension_id
          parts = contribution_identifier&.split(".")
          return nil unless parts && parts.length >= 2

          parts.first(2).join(".")
        end
      end
    end
  end
end
