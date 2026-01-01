# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Opam
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      OPAM_REPO = "https://opam.ocaml.org"

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # Try to find source from opam repository
        dependency.name

        # Check if we can get the source URL from opam file
        source_from_opam_file
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def source_from_opam_file
        # Look for homepage, dev-repo, or bug-reports fields in opam files
        opam_files = dependency_files.select do |f|
          f.name.end_with?(".opam") || f.name == "opam"
        end

        opam_files.each do |file|
          content = file.content

          # Look for dev-repo field
          if (match = content.match(/dev-repo:\s*"([^"]+)"/))
            url = match[1]
            return source_from_url(url)
          end

          # Look for homepage field
          if (match = content.match(/homepage:\s*"([^"]+)"/))
            url = match[1]
            return source_from_url(url)
          end
        end

        nil
      end

      sig { params(url: String).returns(T.nilable(Dependabot::Source)) }
      def source_from_url(url)
        # Parse Git URLs
        if url.include?("github.com")
          Source.from_url(url)
        elsif url.include?("gitlab.com")
          Source.from_url(url)
        end
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("opam", Dependabot::Opam::MetadataFinder)
