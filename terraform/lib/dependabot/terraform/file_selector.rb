# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/terraform/file_filter"

module Dependabot
  module Terraform
    module FileSelector
      extend T::Sig
      extend T::Helpers

      TF_EXTENSION = ".tf"
      OVERRIDE_TF_EXTENSION = "override.tf"

      abstract!

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files; end

      private

      include FileFilter

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terraform_files
        dependency_files.select { |f| f.name.end_with?(TF_EXTENSION) && !f.name.end_with?(OVERRIDE_TF_EXTENSION) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def override_terraform_files
        dependency_files.select { |f| f.name.end_with?(OVERRIDE_TF_EXTENSION) }
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
        params(modules: T::Hash[String, T::Array[T::Hash[String, T.untyped]]],
               base_modules: T::Hash[String,
                                     T::Array[T::Hash[String,
                                                      T.untyped]]])
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
