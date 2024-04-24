# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class PackageName
      extend T::Sig

      # NPM package naming rules are defined by the following projects:
      # - https://github.com/npm/npm-user-validate
      # - https://github.com/npm/validate-npm-package-name
      PACKAGE_NAME_REGEX = %r{
        \A                                          # beginning of string
        (?=.{1,214}\z)                              # enforce length (1 - 214)
        (@(?<scope>                                 # capture 'scope' if present
          [a-z0-9\-\_\.\!\~\*\'\(\)]+               # URL-safe characters in scope
        )\/)?                                       # scope must be followed by slash
        (?<name>                                    # capture package name
          (?(<scope>)                               # if scope is present
            [a-z0-9\-\_\.\!\~\*\'\(\)]+             # scoped names can start with any URL-safe character
          |                                         # if no scope
            [a-z0-9\-\!\~\*\'\(\)]                  # non-scoped names cannot start with . or _
            [a-z0-9\-\_\.\!\~\*\'\(\)]*             # subsequent characters can be any URL-safe character
          )
        )
        \z                                          # end of string
      }xi                                           # multi-line/case-insensitive

      TYPES_PACKAGE_NAME_REGEX = %r{
          \A                                          # beginning of string
          @types\/                                    # starts with @types/
          ((?<scope>.+)__)?                           # capture scope
          (?<name>.+)                                 # capture name
          \z                                          # end of string
      }xi                                             # multi-line/case-insensitive

      class InvalidPackageName < StandardError; end

      sig { params(string: String).void }
      def initialize(string)
        match = PACKAGE_NAME_REGEX.match(string.to_s)
        raise InvalidPackageName unless match

        @scope = T.let(match[:scope], T.nilable(String))
        @name = T.let(match[:name], T.nilable(String))
      end

      sig { returns(String) }
      def to_s
        if scoped?
          "@#{@scope}/#{@name}"
        else
          @name.to_s
        end
      end

      sig { params(other: PackageName).returns(T::Boolean) }
      def eql?(other)
        self.class == other.class && to_s == other.to_s
      end

      sig { returns(Integer) }
      def hash
        to_s.downcase.hash
      end

      sig { params(other: PackageName).returns(T.nilable(Integer)) }
      def <=>(other)
        to_s.casecmp(other.to_s)
      end

      sig { returns(T.nilable(PackageName)) }
      def library_name
        return unless types_package?
        return @library_name if defined?(@library_name)

        lib_name =
          begin
            match = T.must(TYPES_PACKAGE_NAME_REGEX.match(to_s))
            if match[:scope]
              self.class.new("@#{match[:scope]}/#{match[:name]}")
            else
              self.class.new(match[:name].to_s)
            end
          end

        @library_name ||= T.let(lib_name, T.nilable(PackageName))
      end

      sig { returns(T.nilable(PackageName)) }
      def types_package_name
        return if types_package?

        @types_package_name ||= T.let(
          if scoped?
            self.class.new("@types/#{@scope}__#{@name}")
          else
            self.class.new("@types/#{@name}")
          end, T.nilable(PackageName)
        )
      end

      private

      sig { returns(T::Boolean) }
      def scoped?
        !@scope.nil?
      end

      sig { returns(T.nilable(T::Boolean)) }
      def types_package?
        "types".casecmp?(@scope)
      end
    end
  end
end
