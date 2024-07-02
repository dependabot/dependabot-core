# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/nuget/version"
require "dependabot/nuget/requirement"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Nuget
    class TfmComparer
      extend T::Sig

      sig { params(project_tfms: T::Array[String], package_tfms: T::Array[String]).returns(T::Boolean) }
      def self.are_frameworks_compatible?(project_tfms, package_tfms)
        return false if package_tfms.empty?
        return false if project_tfms.empty?

        key = "project_ftms:#{project_tfms.sort.join(',')}:package_tfms:#{package_tfms.sort.join(',')}".downcase

        @cached_framework_check ||= T.let({}, T.nilable(T::Hash[String, T::Boolean]))
        unless @cached_framework_check.key?(key)
          @cached_framework_check[key] =
            NativeHelpers.run_nuget_framework_check(project_tfms,
                                                    package_tfms)
        end
        T.must(@cached_framework_check[key])
      end
    end
  end
end
