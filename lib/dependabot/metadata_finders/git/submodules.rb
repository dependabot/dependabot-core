# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Git
      class Submodules < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          url = dependency.requirements.first.fetch(:source)[:url] ||
                dependency.requirements.first.fetch(source).fetch("url")

          return nil unless url.match?(SOURCE_REGEX)
          captures = url.match(SOURCE_REGEX).named_captures
          Source.new(host: captures.fetch("host"), repo: captures.fetch("repo"))
        end
      end
    end
  end
end
