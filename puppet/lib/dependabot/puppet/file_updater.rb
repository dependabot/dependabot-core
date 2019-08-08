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
        updated_content = puppet_file.content.dup

        dependencies.each do |dep|
          updated_content = update_content(
            updated_content,
            dep.name.gsub('-', '/'),
            dep.previous_version,
            dep.version
          )
        end

        raise "Puppetfile unchanged!" if updated_content == puppet_file.content

        [updated_file(file: puppet_file, content: updated_content)]
      end

      private

      def update_content(content, module_name, previous_version, new_version)
        escaped_previous_version = Regexp.escape(previous_version)

        old_version_regex =
          /
            ^mod\s+['"]#{Regexp.escape(module_name)}['"],\s*
            ['"]#{escaped_previous_version}['"]$
          /mxi

        updated_content = content.gsub(old_version_regex) do |declaration|
          declaration.sub(
            /(?<=['"])#{escaped_previous_version}(?=['"])/,
            new_version
          )
        end
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

Dependabot::FileUpdaters.register("puppet", Dependabot::Puppet::FileUpdater)
