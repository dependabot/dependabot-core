# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module GoModules
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        look_up_source_using_go_list
      end

      def look_up_source_using_go_list
        # Turn off the module proxy for private dependencies
        environment = { "GOPRIVATE" => @goprivate }

        command = + "go list -m -json #{dependency.name}@latest"
        # TODO: Should this be SharedHelpers.run_shell_command() or SharedHelpers.escape_command()?
        # See both usages here back to back: https://github.com/dependabot/dependabot-core/blob/2932de643fc6fb0b3eeac91acc55364bc3c090e0/go_modules/lib/dependabot/go_modules/update_checker/latest_version_finder.rb#L89-L97
        command = SharedHelpers.escape_command(command)

        stdout, stderr, status = Open3.capture3(environment, command)
        handle_subprocess_error(stderr) unless status.success?

        module_metadata_json = stdout
        # Other useful metadata is available, see output from this example: $ go list -m -json golang.org/x/tools@latest
        url = JSON.parse(module_metadata_json["Origin"]["URL"])
        Source.from_url(url) if url
      end

      def handle_subprocess_error(stderr)
        # As we discover errors custom to go list, add handling for them here.
        # See go_mod_updater.rb#handle_subprocess_error for example

        # We don't know what happened so we raise a generic error
        msg = stderr.lines.last(10).join.strip
        raise Dependabot::DependabotError, msg
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("go_modules", Dependabot::GoModules::MetadataFinder)
