# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/kiln/helpers"

module Dependabot
  module Kiln
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
            /^Kilnfile\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if lockfile && lockfile.content != updated_lockfile_content
          updated_files <<
              updated_file(
                  file: lockfile,
                  content: updated_lockfile_content
              )
        end
        # raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def lockfile
        @lockfile ||= get_original_file("Kilnfile.lock")
      end

      def updated_lockfile_content
        return @updated_lockfile_content if @updated_lockfile_content


        Helpers.dir_with_dependencies(dependency_files) do |kilnfile_path, lockfile_path|
          @dependencies.each do |dependency|
            update_release(dependency, kilnfile_path)
          end
          @updated_lockfile_content = File.read(lockfile_path)
        end
      end

      def update_release (dep, kilnfile_path)
        args = ""
        cred = @credentials.find { |cred| cred["type"] == "kiln" }
        cred["variables"].each do |id, key|
          args += " -vr #{id}=#{key}"
        end
        latest_version_details, stderr, status_code = Open3.capture3("kiln update-release --name #{dep.name} --version #{dep.version} -kf #{kilnfile_path} -rd #{kilnfile_path.gsub('Kilnfile', '')}" + args)
      end

      def check_required_files
        raise "No Kilnfile.lock!" unless lockfile
      end
    end
  end
end

Dependabot::FileUpdaters.register("kiln", Dependabot::Kiln::FileUpdater)
