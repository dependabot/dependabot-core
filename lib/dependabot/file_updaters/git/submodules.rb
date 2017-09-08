# frozen_string_literal: true
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Git
      class Submodules < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          []
        end

        def updated_dependency_files
          [updated_file(file: submodule, content: dependency.version)]
        end

        private

        def check_required_files
          %w(.gitmodules).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def submodule
          @submodule ||= dependency_files.find do |file|
            file.name == dependency.name
          end
        end
      end
    end
  end
end
