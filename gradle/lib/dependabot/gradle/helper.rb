# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Gradle
    module Helpers
      extend T::Sig

      sig do
        params(project_dir: String).returns(T::Hash[Symbol, T.untyped])
      end
      def self.list_dependencies(project_dir)
        SharedHelpers.run_helper_subprocess(
          command: gradle_helper_path,
          function: "list_dependencies",
          args: { projectDir: project_dir }
        )
      end

      sig { returns(String) }
      def self.gradle_helper_path
        File.join(__dir__, "../../../gradle/helpers/build/install/gradle-helper/bin/gradle-helper")
      end
    end
  end
end
