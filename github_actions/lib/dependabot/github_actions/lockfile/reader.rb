# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/errors"
require "dependabot/dependency_file"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    module Lockfile
      # Read-only parser for `.github/workflows/actions.lock`. Authoritative only for
      # the workflow paths in its `workflows:` section, so onboarding is decided per
      # path via {#onboarded?}, never repo-wide. Never writes: lockfile generation
      # belongs to the gh-actions-lock engine.
      class Reader
        extend T::Sig

        ParsedObject = T.type_alias { T::Hash[String, Object] }

        # Every commit must carry an explicit hash-algorithm prefix.
        ALGO_PREFIXES = T.let(%w(sha1- sha256-).freeze, T::Array[String])

        # Keys gh-actions-lock requires on every `dependencies` entry. A missing key
        # makes the engine silently discard the whole lockfile in memory and report
        # every workflow as un-onboarded.
        REQUIRED_DEPENDENCY_KEYS = T.let(%w(ref commit owner_id repo_id).freeze, T::Array[String])

        sig { params(content: String).void }
        def initialize(content)
          @content = T.let(content, String)
          @data = T.let(parse, ParsedObject)
        end

        # Returns a Reader for the lockfile in a DependencyFile array, or nil when the
        # repo has no lockfile (whole repo is on the legacy path).
        sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T.nilable(Reader)) }
        def self.from_files(files)
          file = files.find { |f| f.path.delete_prefix("/") == LOCKFILE_PATH }
          return nil unless file

          content = file.content
          return nil if content.nil? || content.strip.empty?

          new(content)
        end

        sig { returns(String) }
        def version
          @data["version"].to_s
        end

        sig { params(path: String).returns(T::Boolean) }
        def onboarded?(path)
          workflows.key?(path)
        end

        # True when the lockfile already pins `action_ref` (an `owner/repo@ref`) under
        # the given workflow path. Discriminates a legitimate new-action skip from a
        # contradictory "lock read as empty" finding.
        sig { params(path: String, action_ref: String).returns(T::Boolean) }
        def pins_action?(path, action_ref)
          return false if action_ref.empty?

          Array(workflows[path]).include?(action_ref)
        end

        # Asserts every `dependencies` entry carries {REQUIRED_DEPENDENCY_KEYS}. A
        # missing key makes the engine silently treat the whole lockfile as empty.
        # Deferred to the relock gate (not the constructor) so a malformed lock
        # covering only untouched workflows never blocks a legacy regex update.
        sig { void }
        def validate_dependency_entries!
          dependencies.each do |key, entry|
            raise parse_error("dependency entry #{key.inspect} is not a mapping") unless entry.is_a?(Hash)

            missing = REQUIRED_DEPENDENCY_KEYS.reject { |field| entry.key?(field) }
            unless missing.empty?
              raise parse_error(
                "dependency entry #{key.inspect} is missing required field(s) #{missing.join(', ')}; " \
                "gh-actions-lock requires #{REQUIRED_DEPENDENCY_KEYS.join(', ')} on every entry or it " \
                "silently treats the whole lockfile as empty"
              )
            end

            commit = entry["commit"].to_s
            next if ALGO_PREFIXES.any? { |prefix| commit.start_with?(prefix) }

            raise parse_error(
              "dependency entry #{key.inspect} has commit #{commit.inspect} without a hash-algorithm prefix " \
              "(expected one of #{ALGO_PREFIXES.join(', ')})"
            )
          end
        end

        private

        sig { returns(ParsedObject) }
        def workflows
          wf = @data["workflows"]
          wf.is_a?(Hash) ? wf : {}
        end

        sig { returns(ParsedObject) }
        def dependencies
          deps = @data["dependencies"]
          deps.is_a?(Hash) ? deps : {}
        end

        sig { returns(ParsedObject) }
        def parse
          parsed = YAML.safe_load(@content)
          raise parse_error("lockfile is not a mapping") unless parsed.is_a?(Hash)

          parsed
        rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
          raise parse_error(e.message)
        end

        sig { params(message: String).returns(Dependabot::DependencyFileNotParseable) }
        def parse_error(message)
          Dependabot::DependencyFileNotParseable.new(LOCKFILE_PATH, message)
        end
      end
    end
  end
end
