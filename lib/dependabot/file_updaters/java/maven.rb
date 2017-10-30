# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Java
      class Maven < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [/^pom\.xml$/]
        end

        def updated_dependency_files
          [updated_file(file: pom, content: updated_pom_content)]
        end

        private

        def check_required_files
          %w(pom.xml).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_pom_content
          # TODO: Update the pom.xml file for the new version requirement
          # (which will be in dependency.requirements if that was set correctly
          # in the updater)
          pom.content
        end

        def pom
          @pom ||= dependency_files.find { |f| f.name == "pom.xml" }
        end
      end
    end
  end
end
