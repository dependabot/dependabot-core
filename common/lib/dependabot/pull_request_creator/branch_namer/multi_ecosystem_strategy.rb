# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pull_request_creator/branch_namer/base"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class MultiEcosystemStrategy < Base
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            files: T::Array[Dependabot::DependencyFile],
            target_branch: T.nilable(String),
            includes_security_fixes: T::Boolean,
            multi_ecosystem_name: String,
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
          includes_security_fixes:,
          multi_ecosystem_name:,
          separator: "/",
          prefix: "dependabot",
          max_length: nil,
          word_separator: nil,
          branch_name_case: nil,
          template: nil
        )
          super(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: separator,
            prefix: prefix,
            max_length: max_length,
            word_separator: word_separator,
            branch_name_case: branch_name_case,
            template: template,
          )

          @multi_ecosystem_name = multi_ecosystem_name
          @includes_security_fixes = includes_security_fixes
        end

        sig { override.returns(String) }
        def new_branch_name
          if template
            return render_from_template(
              vars: template_vars,
              strategy: :multi_ecosystem,
              digest: dependency_digest
            )
          end

          sanitize_branch_name(File.join(prefixes, group_name_with_dependency_digest))
        end

        private

        sig { returns(String) }
        attr_reader :multi_ecosystem_name

        sig { returns(T::Hash[String, String]) }
        def template_vars
          vars = {
            "prefix" => prefix,
            "group_name" => multi_ecosystem_name,
            "name" => multi_ecosystem_name
          }
          vars["target_branch"] = target_branch if target_branch
          vars
        end

        sig { returns(T::Array[String]) }
        def prefixes
          [
            prefix,
            target_branch
          ].compact
        end

        sig { returns(String) }
        def group_name_with_dependency_digest
          if @includes_security_fixes
            "group-security-#{multi_ecosystem_name}-#{dependency_digest}"
          else
            "#{multi_ecosystem_name}-#{dependency_digest}"
          end
        end

        sig { returns(T.nilable(String)) }
        def dependency_digest
          @dependency_digest ||= T.let(
            Digest::MD5.hexdigest(
              dependencies.map do |dependency|
                "#{dependency.name}-#{dependency.removed? ? 'removed' : dependency.version}"
              end.sort.join(",")
            ).slice(0, 10),
            T.nilable(String)
          )
        end
      end
    end
  end
end
