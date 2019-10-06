# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Docker
    module FileUpdaterHelper
      private

      def update_digest_and_tag(file)
        old_declaration_regex = digest_and_tag_regex(old_digest(file))

        file.content.gsub(old_declaration_regex) do |old_dec|
          old_dec.
            gsub("@#{old_digest(file)}", "@#{new_digest(file)}").
            gsub(":#{dependency.previous_version}",
                 ":#{dependency.version}")
        end
      end

      def update_tag(file)
        return unless old_tag(file)

        old_declaration =
          if private_registry_url(file) then "#{private_registry_url(file)}/"
          else ""
          end
        old_declaration += "#{dependency.name}:#{old_tag(file)}"

        old_declaration_regex = tag_regex(old_declaration)

        file.content.gsub(old_declaration_regex) do |old_dec|
          old_dec.gsub(":#{old_tag(file)}", ":#{new_tag(file)}")
        end
      end

      def fetch_file_source(file, reqs)
        reqs.
          find { |req| req[:file] == file.name }.
          fetch(:source)
      end

      def fetch_property_in_file_source(file, reqs, property)
        fetch_file_source(file, reqs).fetch(property)
      end

      def specified_with_digest?(file)
        fetch_file_source(file, dependency.requirements)[:digest]
      end

      def new_digest(file)
        return unless specified_with_digest?(file)

        fetch_property_in_file_source(file, dependency.requirements, :digest)
      end

      def old_digest(file)
        return unless specified_with_digest?(file)

        fetch_property_in_file_source(
          file,
          dependency.previous_requirements,
          :digest
        )
      end

      def digest(file, reqs)
        return unless specified_with_digest?(file)

        fetch_property_in_file_source(file, reqs, :digest)
      end

      def new_tag(file)
        fetch_property_in_file_source(file, dependency.requirements, :tag)
      end

      def old_tag(file)
        fetch_property_in_file_source(
          file,
          dependency.previous_requirements,
          :tag
        )
      end

      def private_registry_url(file)
        fetch_file_source(file, dependency.requirements)[:registry]
      end
    end
  end
end
