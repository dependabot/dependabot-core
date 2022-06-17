# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageName
      # NPM package naming rules are defined by the following projects:
      # - https://github.com/npm/npm-user-validate
      # - https://github.com/npm/validate-npm-package-name
      PACKAGE_NAME_REGEX = %r{
          \A                                          # beginning of string
          (?=.{1,214}\z)                              # enforce length (1 - 214)
          (@(?<scope>                                 # capture 'scope' if present
            (?=[^\.])                                 # reject leading dot
            [a-z0-9\-\_\.\!\~\*\'\(\)]+               # URL-safe characters
          )\/)?
          (?<name>                                    # capture package name
            (?=[^\.\_])                               # reject leading dot or underscore
            [a-z0-9\-\_\.\!\~\*\'\(\)]+               # URL-safe characters
          )
          \z                                          # end of string
      }xi.freeze                                      # multi-line/case-insensitive

      TYPES_PACKAGE_NAME_REGEX = %r{
          \A                                          # beginning of string
          @types\/                                    # starts with @types/
          ((?<scope>.+)__)?                           # capture scope
          (?<name>.+)                                 # capture name
          \z                                          # end of string
      }xi.freeze                                      # multi-line/case-insensitive

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

      def eql?(other)
        self.class == other.class && to_s == other.to_s
      end

      def hash
        to_s.downcase.hash
      end

      def <=>(other)
        to_s.casecmp(other.to_s)
      end

      def library_name
        return unless types_package?

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
        return if types_package?

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
        "types".casecmp?(@scope)
      end
    end
  end
end
