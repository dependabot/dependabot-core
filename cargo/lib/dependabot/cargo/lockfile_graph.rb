# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/logger"
require "dependabot/shared_helpers"

module Dependabot
  module Cargo
    module LockfileGraph
      extend T::Sig

      sig { params(snapshots: T::Hash[String, Dependabot::DependencyFile]).returns(T::Hash[String, Object]) }
      def self.facts(snapshots:)
        inputs = snapshots.map do |name, file|
          content = file.content
          raise ArgumentError, "#{file.name} has no content" unless content

          { name: name, content: content }
        end

        T.cast(
          SharedHelpers.run_helper_subprocess(command: helper_path, function: "lock_graph", args: [inputs]),
          T::Hash[String, Object]
        )
      end

      sig { returns(String) }
      def self.helper_path
        default_path = File.expand_path("../../../helpers/install-dir", __dir__)
        root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
        File.join(root, "cargo/bin/lock-graph")
      end
      private_class_method :helper_path
    end
  end
end
