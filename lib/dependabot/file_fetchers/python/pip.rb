# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        def self.required_files
          %w(requirements.txt)
        end

        private

        def extra_files
          setup_files = []
          unfetchable_files = []

          setup_file_paths.each do |path|
            begin
              path = Pathname.new(File.join(path, "setup.py")).cleanpath.to_path
              setup_files << fetch_file_from_github(path)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_files << path
            end
          end

          if unfetchable_files.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_files
          end

          setup_files
        end

        def setup_file_paths
          requirement_file.scan(/^(?:-e\s)?(?<path>\..*)/).flatten
        end

        def requirement_file
          requirements_file =
            required_files.find { |f| f.name == "requirements.txt" }
          requirements_file.content
        end
      end
    end
  end
end
