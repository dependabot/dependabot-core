# frozen_string_literal: true

require "excon"
require "nokogiri"

require "dependabot/shared_helpers"
require "dependabot/source"
require "dependabot/dep/native_helpers"

module Dependabot
  module Dep
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

      # Used in dependabot-backend, which doesn't have access to any Go
      # helpers.
      # TODO: remove the need for this.
      def self.git_url_for_path_without_go_helper(path)
        # Save a query by manually converting golang.org/x names
        tmp_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

        # Currently, Dependabot::Source.new will return `nil` if it can't
        # find a git SCH associated with a path. If it is ever extended to
        # handle non-git sources we'll need to add an additional check here.
        return Source.from_url(tmp_path).url if Source.from_url(tmp_path)
        return "https://#{tmp_path}" if tmp_path.end_with?(".git")
        return unless (metadata_response = fetch_path_metadata(path))

        # Look for a GitHub, Bitbucket or GitLab URL in the response
        metadata_response.scan(Dependabot::Source::SOURCE_REGEX) do
          source_url = Regexp.last_match.to_s
          return Source.from_url(source_url).url
        end

        # If none are found, parse the response and return the go-import path
        doc = Nokogiri::XML(metadata_response)
        doc.remove_namespaces!
        import_details =
          doc.xpath("//meta").
          find { |n| n.attributes["name"]&.value == "go-import" }&.
          attributes&.fetch("content")&.value&.split(/\s+/)
        return unless import_details && import_details[1] == "git"

        import_details[2]
      end

      def self.fetch_path_metadata(path)
        # TODO: This is not robust! Instead, we should shell out to Go and
        # use https://github.com/Masterminds/vcs.
        response = Excon.get(
          "https://#{path}?go-get=1",
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        return unless response.status == 200

        response.body
      end
      private_class_method :fetch_path_metadata
    end
  end
end
