# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/terraform/file_filter"

module Dependabot
  module Terraform
    module FileSelector
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files; end

      private

      include FileFilter

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terraform_files
        dependency_files.select { |f| f.name.end_with?(".tf") && !f.name.end_with?("override.tf") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def override_terraform_files
        dependency_files.select { |f| f.name.end_with?("override.tf") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terragrunt_files
        dependency_files.select { |f| terragrunt_file?(f.name) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        dependency_files.find { |f| lockfile?(f.name) }
      end

      def merge_modules(modules, base_modules)
        merged_modules = base_modules.dup

        modules.each do |key, value|
          merged_modules[key] = if merged_modules.key?(key)
                                  merged_modules[key].map do |base_value|
                                    base_value.merge(value.first)
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
