# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module CSharp
      class Nuget < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # Hit the registry (or some other source) and get details of the
          # location of the source code for the given dependency
          Source.new(host: "github.com", repo: "my-org/my-dependency")
        end
      end
    end
  end
end
