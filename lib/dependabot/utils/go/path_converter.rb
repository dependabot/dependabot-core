# frozen_string_literal: true

require "excon"
require "dependabot/shared_helpers"
require "dependabot/source"

module Dependabot
  module Utils
    module Go
      module PathConverter
        def self.git_source_for_path(path)
          # Save a query by manually converting golang.org/x names
          tmp_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

          # Currently, Dependabot::Source.new will return `nil` if it can't
          # find a git SCH associated with a path. If it is ever extended to
          # handle non-git sources we'll need to add an additional check here.
          return Source.from_url(tmp_path) if Source.from_url(tmp_path)

          # TODO: This is not robust! Instead, we should shell out to Go and
          # use https://github.com/Masterminds/vcs.
          uri = "https://#{path}?go-get=1"
          response = Excon.get(
            uri,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          return unless response.status == 200

          response.body.scan(Dependabot::Source::SOURCE_REGEX) do
            source_url = Regexp.last_match.to_s
            return Source.from_url(source_url)
          end

          nil
        end
      end
    end
  end
end
