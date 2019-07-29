# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module Puppet
    # Metadata finders look up metadata about a dependency, such as its GitHub URL.
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private
      def look_up_source
        url = nil
        puppet_forge_url = puppet_forge_url(dependency.name)

        begin
          response = Excon.get(
            puppet_forge_url,
            headers: {
              'User-Agent' => 'dependabot-puppet/0.1.0'
            },
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          j = JSON.parse(response.body)

          url = j['homepage_url']
        rescue JSON::ParserError, Excon::Error::Timeout
          url = nil
        end
        Source.from_url(url) if url
      end

      def puppet_forge_url(module_name)
        "https://forgeapi.puppet.com/v3/modules/#{module_name}?exclude_fields=readme,license"
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("puppet", Dependabot::Puppet::MetadataFinder)
