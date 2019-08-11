# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Puppet
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/puppetfile_updater"

      def self.updated_files_regex
        [/^Puppetfile$/]
      end

      def updated_dependency_files
        updated_files = []

        if puppetfile && file_changed?(puppetfile)
          updated_files <<
            updated_file(
              file: puppetfile,
              content: updated_puppetfile_content(puppetfile)
            )
        end

        updated_files
      end

      private

      def updated_puppetfile_content(file)
        PuppetfileUpdater.new(
          dependencies: dependencies,
          puppetfile: file
        ).updated_puppetfile_content
      end

      def check_required_files
        raise "No Puppetfile!" unless puppetfile
      end

      def puppetfile
        @puppetfile ||= get_original_file("Puppetfile")
      end
    end
  end
end

Dependabot::FileUpdaters.register("puppet", Dependabot::Puppet::FileUpdater)
