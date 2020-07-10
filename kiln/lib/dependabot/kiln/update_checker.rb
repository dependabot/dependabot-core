require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/kiln/helpers"

module Dependabot
  module Kiln
    class UpdateChecker < Dependabot::UpdateCheckers::Base

# return most recent version, regardless of requirements
# def latest_version

      def latest_version
        latest_version_details = find_release
        version_class.new(JSON.parse(latest_version_details)["version"])
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        nil
      end

      def updated_requirements
        # This should take new requirements found via latest_version methods
        # and update dependency.requirements to match those requirements
        latest_version_details = find_release
        remote_path = JSON.parse(latest_version_details)["remote_path"]
        source = JSON.parse(latest_version_details)["source"]
        sha = JSON.parse(latest_version_details)["sha"]
        version = JSON.parse(latest_version_details)["version"]

        if version == ''
          return @dependency.requirements
        end

        [{
             requirement: @dependency.requirements[0][:requirement],
             file: @dependency.requirements[0][:file],
             groups: @dependency.requirements[0][:groups],
             source: {
                 type: source,
                 remote_path: remote_path,
                 sha: sha,
             }
         }]
      end

      private

      def find_release
        return @latest_version_details if @latest_version_details
        args = ""
        cred = @credentials.find { |cred| cred["type"] == "kiln" }
        cred["variables"].each do |id, key|
          args += " -vr #{id}=#{key}"
        end

        Helpers.dir_with_dependencies(dependency_files) do |kilnfile_path, lockfile_path|
          latest_version_details, stderr, status_code = Open3.capture3("kiln find-release-version --r #{@dependency.name} -kf #{kilnfile_path}" + args)
          @latest_version_details = latest_version_details.lines.last
        end
      end

      def latest_version_resolvable_with_full_unlock?
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
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
Dependabot::UpdateCheckers.register("kiln", Dependabot::Kiln::UpdateChecker)


