# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class Base
        extend T::Sig

        sig { returns(T::Array[Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :files

        sig { returns(T.nilable(String)) }
        attr_reader :target_branch

        sig { returns(String) }
        attr_reader :separator

        sig { returns(String) }
        attr_reader :prefix

        sig { returns(T.nilable(Integer)) }
        attr_reader :max_length

        sig do
          params(
            dependencies: T::Array[Dependency],
            files: T::Array[DependencyFile],
            target_branch: T.nilable(String),
            separator: String,
            prefix: String,
            max_length: T.nilable(Integer)
          )
            .void
        end
        def initialize(dependencies:, files:, target_branch:, separator: "/",
                       prefix: "dependabot", max_length: nil)
          @dependencies  = dependencies
          @files         = files
          @target_branch = target_branch
          @separator     = separator
          @prefix        = prefix
          @max_length    = max_length
        end

        sig { overridable.returns(String) }
        def new_branch_name
          raise NotImplementedError
        end

        private

        sig { params(ref_name: String).returns(String) }
        def sanitize_branch_name(ref_name)
          # General git ref validation
          sanitized_name = sanitize_ref(ref_name)

          # Some users need branch names without slashes
          sanitized_name = sanitized_name.gsub("/", separator)

          # Shorten the ref in case users refs have length limits
          if max_length && (sanitized_name.length > T.must(max_length))
            sha = T.must(Digest::SHA1.hexdigest(sanitized_name)[0, T.must(max_length)])
            sanitized_name[[T.must(max_length) - sha.size, 0].max..] = sha
          end

          sanitized_name
        end

        sig { params(ref: String).returns(String) }
        def sanitize_ref(ref)
          # This isn't a complete implementation of git's ref validation, but it
          # covers most cases that crop up. Its list of allowed characters is a
          # bit stricter than git's, but that's for cosmetic reasons.
          ref.
            # Remove forbidden characters (those not already replaced elsewhere)
            gsub(%r{[^A-Za-z0-9/\-_.(){}]}, "").
            # Slashes can't be followed by periods
            gsub(%r{/\.}, "/dot-").squeeze(".").squeeze("/").
            # Trailing periods are forbidden
            sub(/\.$/, "")
        end
      end
    end
  end
end
