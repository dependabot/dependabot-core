# frozen_string_literal: true

require "dependabot/go_modules/native_helpers"

module Dependabot
  module GoModules
    module PathConverter
      def self.git_url_for_path(path)
        # Save a query by manually converting golang.org/x names
        import_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

        SharedHelpers.run_helper_subprocess(
          command: NativeHelpers.helper_path,
          function: "getVcsRemoteForImport",
          args: { import: import_path }
        )
      end
    end
  end
end
