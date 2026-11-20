# typed: strict
# frozen_string_literal: true

require "yaml"

require "dependabot/github_actions/workflow_file"
require "dependabot/github_actions/workflow_file/runner_declaration"

module Dependabot
  module GithubActions
    class WorkflowFile
      # Finds the labels written out in each job's `runs-on`, keeping each one's YAML
      # node so the updater can edit it in place.
      class RunsOnCollector
        extend T::Sig

        RUNS_ON_KEY = "runs-on"

        sig { params(content: String).void }
        def initialize(content)
          @content = content
        end

        sig { returns(T::Array[RunnerDeclaration]) }
        def declarations
          jobs = mapping_value(root, "jobs")
          return [] unless jobs.is_a?(Psych::Nodes::Mapping)

          pairs(jobs).flat_map do |job_id, job|
            next [] unless job.is_a?(Psych::Nodes::Mapping) && job.anchor.nil?

            declarations_for(mapping_value(job, RUNS_ON_KEY), ["jobs", job_id, RUNS_ON_KEY])
          end
        end

        private

        # Skip anything anchored, because bumping it would quietly move every job that
        # aliases it. A list with more than one label usually means a self-hosted runner
        # (`[self-hosted, linux]` or `[ubuntu-22.04, gpu]`), and the `group:`/`labels:`
        # form picks larger runners. Neither is a hosted image.
        sig { params(node: T.nilable(Psych::Nodes::Node), path: Path).returns(T::Array[RunnerDeclaration]) }
        def declarations_for(node, path)
          case node
          when Psych::Nodes::Scalar
            node.anchor ? [] : [RunnerDeclaration.new(value: node.value, path: path, node: node)]
          when Psych::Nodes::Sequence
            items = children(node)
            item = items.first
            return [] unless items.one? && node.anchor.nil? && item.is_a?(Psych::Nodes::Scalar)

            declarations_for(item, path + [0])
          else
            []
          end
        end

        sig { returns(T.nilable(Psych::Nodes::Node)) }
        def root
          document = children(YAML.parse_stream(@content)).first
          document && children(document).first
        end

        sig { params(node: T.nilable(Psych::Nodes::Node), key: String).returns(T.nilable(Psych::Nodes::Node)) }
        def mapping_value(node, key)
          return unless node.is_a?(Psych::Nodes::Mapping)

          pairs(node).find { |pair_key, _value| pair_key == key }&.last
        end

        sig { params(node: Psych::Nodes::Mapping).returns(T::Array[[String, Psych::Nodes::Node]]) }
        def pairs(node)
          children(node).each_slice(2).filter_map do |key, value|
            [key.value, value] if key.is_a?(Psych::Nodes::Scalar) && value
          end
        end

        sig { params(node: Psych::Nodes::Node).returns(T::Array[Psych::Nodes::Node]) }
        def children(node)
          nodes = node.children
          nodes.is_a?(Array) ? nodes : []
        end
      end
    end
  end
end
