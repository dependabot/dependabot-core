# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Terraform
    module FileFilter
      extend T::Sig

      sig { params(file_name: String).returns(T::Boolean) }
      def terragrunt_file?(file_name)
        !lockfile?(file_name) && file_name.end_with?(".hcl")
      end

      sig { params(filename: String).returns(T::Boolean) }
      def lockfile?(filename)
        filename == ".terraform.lock.hcl"
      end
    end
  end
end
