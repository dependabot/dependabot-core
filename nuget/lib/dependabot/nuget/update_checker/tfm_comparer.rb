# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/nuget/version"
require "dependabot/nuget/requirement"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Nuget
    class TfmComparer
      def self.are_frameworks_compatible?(project_tfms, package_tfms)
        return false if package_tfms.empty?
        return false if project_tfms.empty?

        key = "project_ftms:#{project_tfms.sort.join(',')}:package_tfms:#{package_tfms.sort.join(',')}".downcase

        @cached_framework_check ||= {}
        unless @cached_framework_check.key?(key)
          @cached_framework_check[key] =
            NativeHelpers.run_nuget_framework_check(project_tfms,
                                                    package_tfms)
        end
        @cached_framework_check[key]
      end
    end
  end
end
