# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/opentofu/file_filter"

module Dependabot
  module Opentofu
    module FileSelector
      extend T::Sig
      extend T::Helpers

      TF_EXTENSION = ".tf"
      TOFU_EXTENSION = ".tofu"
      OVERRIDE_TF_EXTENSION = "override.tf"
      OVERRIDE_TOFU_EXTENSION = "override.tofu"

      abstract!

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files; end

      private

      include FileFilter

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def opentofu_files
        dependency_files.select do |f|
          f.name.end_with?(
            TF_EXTENSION,
            TOFU_EXTENSION
          ) && !f.name.end_with?(OVERRIDE_TF_EXTENSION, OVERRIDE_TOFU_EXTENSION)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def override_opentofu_files
        dependency_files.select { |f| f.name.end_with?(OVERRIDE_TF_EXTENSION, OVERRIDE_TOFU_EXTENSION) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terragrunt_files
        dependency_files.select { |f| terragrunt_file?(f.name) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        dependency_files.find { |f| lockfile?(f.name) }
      end
    end
  end
end
