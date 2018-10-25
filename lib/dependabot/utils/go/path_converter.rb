# frozen_string_literal: true

require "excon"
require "nokogiri"

require "dependabot/shared_helpers"
require "dependabot/source"
require "dependabot/utils/go/shared_helper"

module Dependabot
  module Utils
    module Go
      module PathConverter
        def self.git_url_for_path(path)
          # Save a query by manually converting golang.org/x names
          import_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

          SharedHelpers.run_helper_subprocess(
            command: Go::SharedHelper.path,
            function: "getVcsRemoteForImport",
            args: { import: import_path }
          )
        end
      end
    end
  end
end
