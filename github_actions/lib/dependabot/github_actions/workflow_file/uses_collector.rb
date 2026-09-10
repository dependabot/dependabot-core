# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class WorkflowFile
      class UsesCollector
        extend T::Sig

        class ResolvedUse < T::Struct
          const :value, String
          const :path, Path
        end

        sig { params(data: T.nilable(Object)).void }
        def initialize(data)
          @data = data
        end

        sig { returns(T::Array[ResolvedUse]) }
        def uses
          root, path = workflow_root
          return [] unless root && path

          collect_uses(root, path)
        end

        private

        sig { returns(T.nilable(Object)) }
        attr_reader :data

        sig { returns([T.nilable(Object), T.nilable(Path)]) }
        def workflow_root
          return [nil, nil] unless data.is_a?(Hash)

          workflow_data = T.cast(data, T::Hash[Object, Object])
          if workflow_data.key?("jobs")
            [workflow_data["jobs"], ["jobs"]]
          elsif workflow_data.key?("runs")
            [workflow_data["runs"], ["runs"]]
          else
            [nil, nil]
          end
        end

        sig { params(value: Object, path: Path).returns(T::Array[ResolvedUse]) }
        def collect_uses(value, path)
          case value
          when Hash then collect_uses_from_hash(value, path)
          when Array
            value.each_with_index.flat_map do |child, index|
              collect_uses(child, path + [index])
            end
          else
            []
          end
        end

        sig { params(value: T::Hash[Object, Object], path: Path).returns(T::Array[ResolvedUse]) }
        def collect_uses_from_hash(value, path)
          if value.key?(USES_KEY)
            declaration_value = value[USES_KEY]
            return [] unless declaration_value.is_a?(String)

            [ResolvedUse.new(value: declaration_value, path: path + [USES_KEY])]
          elsif value.key?(STEPS_KEY)
            collect_uses(value[STEPS_KEY], path + [STEPS_KEY])
          else
            value.flat_map { |key, child| collect_uses(child, path + [key.to_s]) }
          end
        end
      end
    end
  end
end
