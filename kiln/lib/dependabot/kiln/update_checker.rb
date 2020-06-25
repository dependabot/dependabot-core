require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Kiln
    class UpdateChecker < Dependabot::UpdateCheckers::Base

# return most recent version, regardless of requirements
# def latest_version

      def latest_version
        s, c = Open3.capture2("kiln fetch-latest-version uaa", nil)
        return s
        #latest_version_details&.fetch(:version)
      end

      def latest_resolvable_version
        ""
      end

      def latest_resolvable_version_with_no_unlock
        ""
      end

      def updated_requirements
        ""
      end

      def latest_version_resolvable_with_full_unlock?
        false
      end

# we think this is the most recent version that meets the version requirements
# def latest_resolvable_version
#
# we think this is the same as the above, but possibly is supposed to take
# into account nested dependencies and ensure none of them become invalid by
# upgrading this dependency. We think this does not apply to us since we don't
# have nested dependencies, we can probably just alias the above method
# def latest_resolvable_version_with_no_unlock

    end
  end
end

