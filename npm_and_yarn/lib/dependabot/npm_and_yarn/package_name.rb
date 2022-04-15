# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageName
      DEFINITELY_TYPED_SCOPE = /types/i
      PACKAGE_NAME_REGEX     = %r{
          \A                                         # beginning of string
          (?=.{1,214}\z)                             # enforce length (1 - 214)
          (@(?<scope>[a-z0-9\-~][a-z0-9\-\._~]*)\/)? # capture 'scope' if present
          (?<name>[a-z0-9\-~][a-z0-9\-._~]*)         # capture package name
          \z                                         # end of string
      }xi.freeze                                     # multi-line/case-insensitive

      class InvalidPackageName < StandardError; end

      def initialize(string)
        match = PACKAGE_NAME_REGEX.match(string.to_s)
        raise InvalidPackageName unless match

        @scope = match[:scope]
        @name  = match[:name]
      end

      def types_package
        return if types_package?

        if scoped?
          "@types/#{@scope}__#{@name}"
        else
          "@types/#{@name}"
        end
      end

      private

      def scoped?
        !@scope.nil?
      end

      def types_package?
        DEFINITELY_TYPED_SCOPE.match?(@scope)
      end
    end
  end
end
