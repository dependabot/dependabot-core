# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    module Go
      class Dep < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          return look_up_git_dependency_source if git_dependency?

          source_string = (specified_source_string || dependency.name).
                          gsub(%r{^golang\.org/x}, "github.com/golang")

          Source.from_url(source_string)
        end

        def git_dependency?
          return false unless declared_source_details

          dependency_type =
            declared_source_details.fetch(:type, nil) ||
            declared_source_details.fetch("type")

          dependency_type == "git"
        end

        def look_up_git_dependency_source
          specified_url =
            declared_source_details.fetch(:url, nil) ||
            declared_source_details.fetch("url")

          Source.from_url(specified_url)
        end

        def specified_source_string
          declared_source_details&.fetch(:source, nil) ||
            declared_source_details&.fetch("source", nil)
        end

        def declared_source_details
          sources = dependency.requirements.
                    map { |r| r.fetch(:source) }.
                    uniq.compact

          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          sources.first
        end
      end
    end
  end
end
