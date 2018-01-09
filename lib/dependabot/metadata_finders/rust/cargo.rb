# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Rust
      class Cargo < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # Hit the registry (or some other source) and get details of the
          # location of the source code for the given dependency. For a good
          # example, see Java or Python, both of which are pretty simple.
          Source.new(host: "github.com", repo: "my-org/my-dependency")
        end
      end
    end
  end
end
