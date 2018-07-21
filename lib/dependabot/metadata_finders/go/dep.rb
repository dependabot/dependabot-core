# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Go
      class Dep < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          # TODO: A more general way to do this?
          source_string = specified_source_string.
                          gsub(%r{^golang\.org/x}, "github.com/golang")

          Source.from_url(source_string)
        end

        def specified_source_string
          sources = dependency.requirements.
                    map { |r| r.fetch(:source) }.uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first&.fetch(:source, nil) ||
            sources.first&.fetch("source") ||
            dependency.name
        end
      end
    end
  end
end
