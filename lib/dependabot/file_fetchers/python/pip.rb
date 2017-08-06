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
          setup_file_required? ? [fetch_file_from_github("setup.py")] : []
        end

        def setup_file_required?
          requirements_file =
            required_files.find { |f| f.name == "requirements.txt" }
          requirements_file.content.match?(/^-e \./)
        end
      end
    end
  end
end
