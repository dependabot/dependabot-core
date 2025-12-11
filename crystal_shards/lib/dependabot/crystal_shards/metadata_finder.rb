# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

module Dependabot
  module CrystalShards
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source_from_dependency || source_from_git_url
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def source_from_dependency
        source_info = dependency.requirements
                                .filter_map { |r| r[:source] }
                                .first

        return nil unless source_info.is_a?(Hash)

        url = source_info[:url]
        return nil unless url.is_a?(String)

        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def source_from_git_url
        return nil unless dependency.respond_to?(:metadata)

        metadata = dependency.metadata
        return nil unless metadata.is_a?(Hash)

        url = metadata[:source_url]
        return nil unless url.is_a?(String)

        Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("crystal_shards", Dependabot::CrystalShards::MetadataFinder)
