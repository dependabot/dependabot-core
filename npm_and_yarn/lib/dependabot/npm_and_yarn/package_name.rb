# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageName
      DEFINITELY_TYPED_SCOPE = /types/i.freeze
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

      def to_s
        if scoped?
          "@#{@scope}/#{@name}"
        else
          @name.to_s
        end
      end

      def <=>(other)
        to_s <=> other.to_s
      end

      def types_package
        return self if types_package?

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
