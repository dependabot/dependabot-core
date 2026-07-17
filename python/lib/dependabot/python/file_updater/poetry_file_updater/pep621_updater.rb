# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/file_updater/poetry_file_updater"

module Dependabot
  module Python
    class FileUpdater
      class PoetryFileUpdater
        class Pep621Updater
          extend T::Sig

          sig { params(dep: Dependabot::Dependency).void }
          def initialize(dep:)
            @dep = dep
          end

          sig do
            params(
              content: String,
              new_r: T::Hash[Symbol, T.untyped],
              old_r: T::Hash[Symbol, T.untyped]
            ).returns(T.nilable(String))
          end
          def replace(content, new_r, old_r)
            source_req = dep.metadata[:source_requirement]

            if source_req
              replace_with_source_requirement(content, source_req, new_r, old_r)
            else
              replace_with_normalized_requirement(content, new_r, old_r)
            end
          end

          sig { params(source_req: String, old_req: String, new_req: String).returns(String) }
          def rewrite_pep508_requirement(source_req, old_req, new_req)
            old_specifiers = parse_specifiers(old_req)
            new_specifiers = parse_specifiers(new_req)

            old_versions_by_op = group_versions_by_operator(old_specifiers)
            new_versions_by_op = group_versions_by_operator(new_specifiers)

            replacements = T.let([], T::Array[T::Hash[Symbol, String]])
            new_versions_by_op.each do |operator, new_versions|
              old_versions = old_versions_by_op[operator]
              next unless old_versions
              next unless old_versions.length == new_versions.length

              old_versions.zip(new_versions).each do |old_version, new_version|
                next if old_version == new_version

                replacements << {
                  operator: operator,
                  old_version: old_version,
                  new_version: T.must(new_version)
                }
              end
            end

            result = source_req.dup
            replacements.each do |replacement|
              op = Regexp.escape(T.must(replacement[:operator]))
              ver = Regexp.escape(T.must(replacement[:old_version]))
              result = result.sub(/(#{op}\s*)#{ver}/, "\\1#{replacement[:new_version]}")
            end
            result
          end

          sig { params(specifiers: T::Array[T::Hash[Symbol, String]]).returns(T::Hash[String, T::Array[String]]) }
          def group_versions_by_operator(specifiers)
            specifiers.each_with_object(
              T.let({}, T::Hash[String, T::Array[String]])
            ) do |specifier, grouped_versions|
              operator = T.must(specifier[:operator])
              version = T.must(specifier[:version])

              grouped_versions[operator] ||= []
              T.must(grouped_versions[operator]) << version
            end
          end

          sig { params(req: String).returns(T::Array[T::Hash[Symbol, String]]) }
          def parse_specifiers(req)
            req.scan(/([!<>=~]+)\s*([^\s,]+)/).map do |op, ver|
              { operator: op, version: ver }
            end
          end

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dep

          sig do
            params(
              content: String,
              source_req: String,
              new_r: T::Hash[Symbol, T.untyped],
              old_r: T::Hash[Symbol, T.untyped]
            ).returns(T.nilable(String))
          end
          def replace_with_source_requirement(content, source_req, new_r, old_r)
            match = content.match(declaration_regex(source_req))
            return unless match

            declaration = T.must(match[:declaration])
            new_req_str = rewrite_pep508_requirement(source_req, old_r[:requirement], new_r[:requirement])
            content.sub(declaration, declaration.sub(source_req, new_req_str))
          end

          # Fallback when source_requirement metadata is absent (e.g. after
          # DependencySet merge or deserialization). Matches using the
          # normalized requirement string, which may fail on whitespace
          # differences but is better than skipping the update entirely.
          sig do
            params(
              content: String,
              new_r: T::Hash[Symbol, T.untyped],
              old_r: T::Hash[Symbol, T.untyped]
            ).returns(T.nilable(String))
          end
          def replace_with_normalized_requirement(content, new_r, old_r)
            old_req = old_r[:requirement]
            new_req = new_r[:requirement]

            match = content.match(normalized_declaration_regex(old_req))
            return unless match

            declaration = T.must(match[:declaration])
            return unless declaration.include?(old_req)

            content.sub(declaration, declaration.sub(old_req, new_req))
          end

          sig { params(old_req: String).returns(Regexp) }
          def declaration_regex(old_req)
            /(?<declaration>["']#{escape}\s*#{extras_pattern}\s*#{Regexp.escape(old_req)}["'])/mi
          end

          sig { params(old_req: String).returns(Regexp) }
          def normalized_declaration_regex(old_req)
            /(?<declaration>["']#{escape}#{extras_pattern}#{Regexp.escape(old_req)}["'])/mi
          end

          sig { returns(String) }
          def extras_pattern
            extras_str = dep.metadata[:extras]
            return "" unless extras_str.is_a?(String) && !extras_str.empty?

            "\\[" + extras_str.split(",").map { |e| Regexp.escape(e.strip) }.join(",\\s*") + "\\]"
          end

          sig { returns(String) }
          def escape
            Regexp.escape(dep.name).gsub("\\-", "[-_.]")
          end
        end
      end
    end
  end
end
