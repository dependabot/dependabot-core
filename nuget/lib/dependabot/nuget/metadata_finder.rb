# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Nuget
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source_url = dependency_source_url
        return Source.from_url(source_url) if source_url

        nil
      end

      sig { returns(T.nilable(String)) }
      def dependency_source_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        return unless source
        return source.fetch(:source_url) if source.key?(:source_url)

        source.fetch("source_url")
      end
    end
  end
end

Dependabot::MetadataFinders.register("nuget", Dependabot::Nuget::MetadataFinder)
