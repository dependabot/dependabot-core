# typed: strong
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class BranchNameTemplate
      extend T::Sig

      class Error < Dependabot::DependabotError; end

      SOLO_PLACEHOLDERS = T.let(
        %w[prefix package_manager directory target_branch dependency version name].freeze,
        T::Array[String]
      )
      GROUP_PLACEHOLDERS = T.let(
        %w[prefix package_manager directory target_branch group_name name].freeze,
        T::Array[String]
      )
      MULTI_ECO_PLACEHOLDERS = T.let(
        %w[prefix target_branch group_name name].freeze,
        T::Array[String]
      )

      # ---------------------------------------------------------------
      # 1. validate_template(template, strategy:)
      #    Ensures every {token} is allowed for the given strategy,
      #    brackets are well-formed, and no forbidden placeholders used.
      # ---------------------------------------------------------------
      sig { params(template: String, strategy: Symbol).returns(T::Boolean) }
      def self.validate_template(template, strategy:)
        raise Error, "Template must be a non-empty string." if template.empty?

        allowed = case strategy
                  when :solo then SOLO_PLACEHOLDERS
                  when :group then GROUP_PLACEHOLDERS
                  when :multi_ecosystem then MULTI_ECO_PLACEHOLDERS
                  else
                    raise Error, "Unknown strategy: #{strategy}"
                  end

        used = template.scan(/\{(\w+)\}/).flatten
        unknown = used.uniq.reject { |t| allowed.include?(t) }
        malformed = template.gsub(/\{\w+\}/, "").match?(/[{}]/)

        messages = T.let([], T::Array[String])
        messages << "Unknown placeholder(s): #{unknown.map { |v| "{#{v}}" }.join(', ')}" unless unknown.empty?
        messages << "Malformed or unclosed braces detected." if malformed

        if strategy == :multi_ecosystem && used.include?("package_manager")
          messages << "{package_manager} is not available for multi-ecosystem groups (spans multiple ecosystems)."
        end

        if messages.any?
          raise Error, "#{messages.join("\n")}\nAllowed: #{allowed.map { |v| "{#{v}}" }.join(', ')}"
        end

        true
      end

      # ---------------------------------------------------------------
      # 2. validate_ref_name(name)
      #    Validates the final branch name against Git ref rules.
      # ---------------------------------------------------------------
      sig { params(name: String).returns(T::Boolean) }
      def self.validate_ref_name(name)
        illegal = %r{
          [\x00-\x1F\x7F\ ~^:?*\[\\] |
          \.\.                         |
          @\{                          |
          //                           |
          \A/                          |
          /\z                          |
          \.lock\z                     |
          \A-                          |
          \.\z                         |
          \A@\z
        }x

        if name.match?(illegal)
          raise Error, "Resolved branch name \"#{name}\" is not a valid Git ref."
        end

        true
      end

      # ---------------------------------------------------------------
      # 3. render(template, vars, strategy:, digest: nil, max_length: nil)
      #    Full pipeline: validate template -> substitute -> append digest
      #    -> validate ref -> apply max-length.
      # ---------------------------------------------------------------
      sig do
        params(
          template: String,
          vars: T::Hash[String, String],
          strategy: Symbol,
          digest: T.nilable(String),
          max_length: T.nilable(Integer)
        ).returns(String)
      end
      def self.render(template, vars, strategy:, digest: nil, max_length: nil)
        validate_template(template, strategy: strategy)

        # Substitute placeholders
        name = template.gsub(/\{(\w+)\}/) do
          key = T.must(Regexp.last_match(1))
          raise Error, "Missing value for placeholder \"{#{key}}\"." unless vars.key?(key)

          T.must(vars[key])
        end

        # Auto-append digest for Group/MultiEcosystem
        if digest && strategy != :solo
          name = "#{name}-#{digest}"
        end

        # Validate git ref
        validate_ref_name(name)

        # Max-length truncation (preserve digest at tail)
        if max_length && name.length > max_length
          if digest && strategy != :solo
            suffix = "-#{digest}"
            available = max_length - suffix.length - 11
            sha = T.must(Digest::SHA1.hexdigest(name)[0, 10])
            name = "#{name[0...available]}-#{sha}#{suffix}"
          else
            sha = Digest::SHA1.hexdigest(name)
            name = "#{name[0...(max_length - 41)]}-#{sha}"
          end
        end

        name
      end
    end
  end
end
