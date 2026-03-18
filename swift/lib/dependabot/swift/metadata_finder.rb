# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "sorbet-runtime"

module Dependabot
  module Swift
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "registry" then find_source_from_registry
        when "default", nil
          # For dependencies without explicit source info (e.g., Xcode-managed
          # SPM dependencies parsed from Package.resolved), attempt to infer
          # source from the dependency name which is typically a normalized URL
          find_source_from_dependency_name
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        info = dependency.source_details

        url = info&.fetch(:url, nil) || info&.fetch("url")
        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_dependency_name
        name = dependency.name
        return nil unless name.include?("/")

        url = "https://#{name}"
        Source.from_url(url)
      end

      sig { returns(T.noreturn) }
      def find_source_from_registry
        raise NotImplementedError
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("swift", Dependabot::Swift::MetadataFinder)
