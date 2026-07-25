# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    module Package
      # A single major version of an Azure Pipelines task, as declared by the
      # `task.json` in its directory.
      class TaskDefinition < T::Struct
        extend T::Sig

        const :directory, String
        const :name, String
        const :version, Dependabot::AzurePipelines::Version
        const :id, T.nilable(String)
        const :deprecated, T::Boolean, default: false
      end
    end
  end
end
