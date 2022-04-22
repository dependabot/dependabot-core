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
      TYPES_PACKAGE_NAME_REGEX = %r{
          \A                                         # beginning of string
          @#{DEFINITELY_TYPED_SCOPE}\/               # starts with @types/
          ((?<scope>.+)__)?                          # capture scope
          (?<name>.+)                                # capture name
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
        to_s.casecmp(other.to_s)
      end

      def eql?(other)
        to_s.eql?(other.to_s)
      end

      def library_name
        return self unless types_package?

        @library_name ||=
          begin
            match = TYPES_PACKAGE_NAME_REGEX.match(to_s)
            if match[:scope]
              self.class.new("@#{match[:scope]}/#{match[:name]}")
            else
              self.class.new(match[:name].to_s)
            end
          end
      end

      def types_package_name
        return self if types_package?

        @types_package_name ||=
          if scoped?
            self.class.new("@types/#{@scope}__#{@name}")
          else
            self.class.new("@types/#{@name}")
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
