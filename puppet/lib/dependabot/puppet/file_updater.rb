# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Puppet
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
          /^Puppetfile$/,
        ]
      end

      def updated_dependency_files
        updated_files = []
        updated_content = dependency_files[0].content.dup

        # require 'pry';binding.pry
        dependencies.each do |dependency|
          # require 'pry';binding.pry
          updated_content = update_content(
            updated_content,
            dependency.name.gsub('-', '/'),
            dependency.previous_version,
            dependency.version
          )

        end
        # require 'pry';binding.pry

        updated_files << updated_file(
          file: puppet_file,
          content: updated_content
        )

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private
      def update_content(content, module_name, previous_version, new_version)
        old_version_regex  = %r{^mod ['\"]#{module_name}['\"],\s*['\"]#{previous_version}['\"]$}i
        new_version_string = "mod \"#{module_name}\", '#{new_version}'"

        updated_content = content.gsub(old_version_regex, new_version_string)
        updated_content
      end

      def check_required_files
        raise "No Puppetfile!" unless puppet_file
      end

      def puppet_file
        @puppet_file ||= get_original_file("Puppetfile")
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("puppet", Dependabot::Puppet::FileUpdater)
