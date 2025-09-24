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

      sig do
        params(
          modules: T::Hash[String, T::Array[T::Hash[String, T.untyped]]],
          base_modules: T::Hash[String,
                                T::Array[T::Hash[String,
                                                 T.untyped]]]
        )
          .returns(T::Hash[String,
                           T::Array[T::Hash[String,
                                            T.untyped]]])
      end
      def merge_modules(modules, base_modules)
        merged_modules = base_modules.dup

        modules.each do |key, value|
          merged_modules[key] =
            if merged_modules.key?(key)
              T.must(merged_modules[key]).map do |base_value|
                base_value.merge(T.must(value.first))
              end
            else
              value
            end
        end

        merged_modules
      end
    end
  end
end
