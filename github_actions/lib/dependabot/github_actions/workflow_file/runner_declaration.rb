# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class WorkflowFile
      class RunnerDeclaration < T::Struct
        const :value, String
        const :path, Path
        const :node, Psych::Nodes::Scalar
      end
    end
  end
end
