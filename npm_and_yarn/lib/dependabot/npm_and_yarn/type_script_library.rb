# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class TypeScriptLibrary
      INVALID_CHARACTERS_REGEX = /[~()'!\*[[:space:]]]/.freeze
      MAX_PACKAGE_NAME_LENGTH  = 214
      TYPES_ORG                = "@types/"

      def initialize(package_name)
        @package_name = package_name.to_s
      end

      def types_package
        return "" if !valid?

        case
        when scoped_library?
          "@types/#{scoped_name}"
        when types_package?
          package_name
        else
          "@types/#{package_name}"
        end
      end

      private

      attr_reader :package_name

      def valid?
        valid_length? && lowercased? && characters_valid?
      end

      def valid_length?
        package_name.length.positive? &&
          package_name.length <= MAX_PACKAGE_NAME_LENGTH
      end

      def lowercased?
        package_name == package_name.downcase
      end

      def characters_valid?
        !package_name.start_with?("_", ".") &&
          !package_name.match?(INVALID_CHARACTERS_REGEX)
      end

      def scoped_library?
        package_name.start_with?("@") && !types_package?
      end

      def types_package?
        package_name.start_with?(TYPES_ORG)
      end

      def scoped_name
        scoped_name_without_at = package_name.delete_prefix("@")
        scope, package = scoped_name_without_at.split("/")
        "#{scope}__#{package}"
      end
    end
  end
end
