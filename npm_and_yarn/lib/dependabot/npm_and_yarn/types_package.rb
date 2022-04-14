# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class TypesPackage
      INVALID_CHARACTERS_REGEX = /[~()'!\*[[:space:]]]/.freeze
      MAX_PACKAGE_NAME_LENGTH  = 214
      TYPES_ORG                = "@types/"

      def initialize(package_name)
        @package_name = package_name.to_s
      end

      def library
        return "" if !valid?

        case
        when scoped_typings_package?
          unscoped_name_without_types_org
        when typings_package?
          name_without_types_org
        else
          ""
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
          !name_without_types_org.start_with?("_", ".") &&
          !package_name.match?(INVALID_CHARACTERS_REGEX)
      end

      def scoped_typings_package?
        typings_package? && name_without_types_org.include?("__")
      end

      def typings_package?
        package_name.start_with?("#{TYPES_ORG}")
      end

      def unscoped_name_without_types_org
        scope, package = name_without_types_org.split("__")
        "@#{scope}/#{package}"
      end

      def name_without_types_org
        package_name.sub(%r{^#{TYPES_ORG}}, "")
      end
    end
  end
end
