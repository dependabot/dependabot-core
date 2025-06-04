# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/go_modules/native_helpers"

module Dependabot
  module GoModules
    module PathConverter
      extend T::Sig

      sig do
        params(path: String)
          .returns(
            T.nilable(String)
          )
      end
      def self.git_url_for_path(path)
        # Save a query by manually converting golang.org/x names
        import_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

        T.cast(
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "getVcsRemoteForImport",
            args: { import: import_path }
          ),
          T.nilable(String)
        )
      end
    end
  end
end
