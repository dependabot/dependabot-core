# typed: strong
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

require "dependabot/pull_request_creator/branch_name_template"

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

        sig { returns(T.nilable(String)) }
        attr_reader :word_separator

        sig { returns(T.nilable(String)) }
        attr_reader :branch_name_case

        sig { returns(T.nilable(String)) }
        attr_reader :template

        sig do
          params(
            dependencies: T::Array[Dependency],
            files: T::Array[DependencyFile],
            target_branch: T.nilable(String),
            separator: String,
            prefix: String,
            max_length: T.nilable(Integer),
            word_separator: T.nilable(String),
            branch_name_case: T.nilable(String),
            template: T.nilable(String)
          )
            .void
        end
        def initialize(
          dependencies:,
          files:,
          target_branch:,
          separator: "/",
          prefix: "dependabot",
          max_length: nil,
          word_separator: nil,
          branch_name_case: nil,
          template: nil
        )
          @dependencies      = dependencies
          @files             = files
          @target_branch     = target_branch
          @separator         = separator
          @prefix            = prefix
          @max_length        = max_length
          @word_separator    = word_separator
          @branch_name_case  = branch_name_case
          @template          = template
        end

        sig { overridable.returns(String) }
        def new_branch_name
          raise NotImplementedError
        end

        private

        sig do
          params(
            vars: T::Hash[String, String],
            strategy: Symbol,
            digest: T.nilable(String)
          ).returns(String)
        end
        def render_from_template(vars:, strategy:, digest: nil)
          rendered = BranchNameTemplate.render(
            T.must(template),
            vars,
            strategy: strategy,
            digest: digest
          )

          # Apply post-processing (separator, word_separator, case) and max-length
          sanitize_branch_name(rendered)
        end

        sig { params(ref_name: String).returns(String) }
        def sanitize_branch_name(ref_name)
          # General git ref validation
          sanitized_name = sanitize_ref(ref_name)

          # Some users need branch names without slashes
          sanitized_name = sanitized_name.gsub("/", separator)

          # Apply word_separator and case transformation only to content after the prefix,
          # preserving the user-configured prefix as-is.
          if word_separator || branch_name_case
            prefix_with_sep = "#{prefix}#{separator}"
            if sanitized_name.start_with?(prefix_with_sep)
              prefix_part = prefix_with_sep
              content = sanitized_name[prefix_with_sep.length..]
            else
              prefix_part = ""
              content = sanitized_name
            end

            # Replace underscores with word_separator in the content after prefix
            content = T.must(content).gsub("_", T.must(word_separator)) if word_separator

            # Apply case transformation to content after prefix
            case branch_name_case
            when "lower"
              content = T.must(content).downcase
            when "upper"
              content = T.must(content).upcase
            end

            sanitized_name = "#{prefix_part}#{content}"
          end

          # Shorten the ref in case users refs have length limits
          branch_name_max_length = max_length
          if branch_name_max_length && (sanitized_name.length > branch_name_max_length)
            sha = T.must(Digest::SHA1.hexdigest(sanitized_name)[0, branch_name_max_length])
            sanitized_name[[branch_name_max_length - sha.size, 0].max..] = sha
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
