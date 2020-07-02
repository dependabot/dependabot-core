require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Kiln
    class UpdateChecker < Dependabot::UpdateCheckers::Base

# return most recent version, regardless of requirements
# def latest_version

      def latest_version
        args = ""
        cred = @credentials.find { |cred| cred["type"] == "kiln" }
        cred["variup_to_dateup_to_dateables"].each do |id, key|
          args += " -vr #{id}=#{key}"
        end

        latest_version_details, c = Open3.capture2("find-release-version --r #{@dependency.name}" + args, nil)
        JSON.parse(latest_version_details)["version"]
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        latest_version
      end

      def updated_requirements
        ""
          # This should take new requirements found via latest_version methods
          # and update dependency.requirements to match those requirements
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

