# typed: true
# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class Base
        attr_reader :dependencies, :files, :target_branch, :separator, :prefix, :max_length

        def initialize(dependencies:, files:, target_branch:, separator: "/",
                       prefix: "dependabot", max_length: nil)
          @dependencies  = dependencies
          @files         = files
          @target_branch = target_branch
          @separator     = separator
          @prefix        = prefix
          @max_length    = max_length
        end

        private

        def sanitize_branch_name(ref_name)
          # General git ref validation
          sanitized_name = sanitize_ref(ref_name)

          # Some users need branch names without slashes
          sanitized_name = sanitized_name.gsub("/", separator)

          # Shorten the ref in case users refs have length limits
          if max_length && (sanitized_name.length > max_length)
            sha = Digest::SHA1.hexdigest(sanitized_name)[0, max_length]
            sanitized_name[[max_length - sha.size, 0].max..] = sha
          end

          sanitized_name
        end

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
