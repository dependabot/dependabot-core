# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/poetry_project"

module Dependabot
  module Python
    class FileUpdater
      class PoetryFileUpdater
        # Rewrites `pyproject.toml` dependency declarations through the native
        # helper's `update_poetry_declarations` function, which edits the file
        # with tomlkit instead of regexes.
        #
        # Requirements the helper can't find are returned so the caller can try
        # its regex path. Only used when the `enable_native_poetry_helper`
        # experiment is on.
        class NativeDeclarationUpdater
          extend T::Sig

          Edit = T.type_alias { T::Hash[String, T.nilable(T.any(String, T::Array[String]))] }

          RequirementPair = T.type_alias do
            [Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]
          end

          class Result < T::ImmutableStruct
            const :content, String
            # Pairs the helper couldn't apply. The caller should try its own
            # path for these.
            const :unapplied, T::Array[RequirementPair]
          end

          BOOLEANS = [true, false].freeze

          # Edits the changed requirements declared in `file_name`. Leaves every
          # pair for the caller's regex path when the experiment is off or the
          # helper fails.
          sig { params(dependency: Dependabot::Dependency, content: String, file_name: String).returns(Result) }
          def self.update_if_enabled(dependency, content, file_name)
            pairs = requirement_pairs(dependency, file_name)
            return Result.new(content: content, unapplied: pairs) unless PoetryProject.enabled?

            begin
              new(dependency: dependency).update(content, pairs)
            rescue SharedHelpers::HelperSubprocessFailed => e
              Dependabot.logger.warn("Native Poetry declaration update failed, using regexes: #{e.message}")
              Result.new(content: content, unapplied: pairs)
            end
          end

          sig { params(dependency: Dependabot::Dependency, file_name: String).returns(T::Array[RequirementPair]) }
          def self.requirement_pairs(dependency, file_name)
            dependency.requirements.zip(T.must(dependency.previous_requirements)).filter_map do |new_r, old_r|
              next unless new_r.file == file_name && T.must(old_r).file == file_name

              [new_r, T.must(old_r)]
            end
          end

          sig { params(dependency: Dependabot::Dependency).void }
          def initialize(dependency:)
            @dependency = dependency
          end

          sig { params(content: String, pairs: T::Array[RequirementPair]).returns(Result) }
          def update(content, pairs)
            supported, unsupported = pairs.partition { |new_r, old_r| edit_for(new_r, old_r) }
            return Result.new(content: content, unapplied: pairs) if supported.empty?

            response = run_helper(content, supported.map { |new_r, old_r| T.must(edit_for(new_r, old_r)) })
            applied = response.fetch(:applied)
            Result.new(
              content: response.fetch(:content),
              unapplied: unsupported + supported.reject.with_index { |_pair, index| applied[index] }
            )
          end

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig do
            params(
              new_r: Dependabot::DependencyRequirement,
              old_r: Dependabot::DependencyRequirement
            ).returns(T.nilable(Edit))
          end
          def edit_for(new_r, old_r)
            # A nil group makes the helper search every dependency table.
            base = { "name" => dependency.name, "group" => old_r.groups&.first, "extras" => extras }
            if git?(new_r) && git?(old_r)
              old_tag = old_r.source_string("ref")
              new_tag = new_r.source_string("ref")
              return old_tag && new_tag ? base.merge("old_tag" => old_tag, "new_tag" => new_tag) : nil
            end

            old_req = old_r.requirement_string
            new_req = new_r.requirement_string
            return unless old_req && new_req

            base.merge("old_requirement" => old_req, "new_requirement" => new_req)
          end

          sig { params(req: Dependabot::DependencyRequirement).returns(T::Boolean) }
          def git?(req)
            req.source_string("type") == "git"
          end

          sig { returns(T::Array[String]) }
          def extras
            value = dependency.metadata[:extras]
            value.is_a?(String) ? value.split(",").map(&:strip) : []
          end

          sig do
            params(
              content: String,
              edits: T::Array[Edit]
            ).returns({ content: String, applied: T::Array[T::Boolean] })
          end
          def run_helper(content, edits)
            result = SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
              function: "update_poetry_declarations",
              args: [content, edits]
            )
            parse_result(result, edits.length)
          end

          sig do
            params(result: T.nilable(Object), expected: Integer)
              .returns({ content: String, applied: T::Array[T::Boolean] })
          end
          def parse_result(result, expected)
            raise TypeError, "update_poetry_declarations result must be an object" unless result.is_a?(Hash)

            content = result["content"]
            applied = result["applied"]
            raise TypeError, "update_poetry_declarations content must be a string" unless content.is_a?(String)
            unless applied.is_a?(Array) && applied.length == expected && applied.all? { |a| BOOLEANS.include?(a) }
              raise TypeError, "update_poetry_declarations applied must be #{expected} booleans"
            end

            { content: content, applied: applied.map { |a| a == true } }
          end
        end
      end
    end
  end
end
