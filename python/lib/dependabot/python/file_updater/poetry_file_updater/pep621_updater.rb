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
            return unless source_req

            match = content.match(declaration_regex(source_req))
            return unless match

            declaration = T.must(match[:declaration])
            new_req_str = rewrite_pep508_requirement(source_req, old_r[:requirement], new_r[:requirement])
            content.sub(declaration, declaration.sub(source_req, new_req_str))
          end

          sig { params(source_req: String, old_req: String, new_req: String).returns(String) }
          def rewrite_pep508_requirement(source_req, old_req, new_req)
            old_specifiers = parse_specifiers(old_req)
            new_specifiers = parse_specifiers(new_req)

            version_map = {}
            old_specifiers.each_with_index do |old_spec, i|
              new_spec = new_specifiers[i]
              next unless new_spec && old_spec[:operator] == new_spec[:operator]
              next if old_spec[:version] == new_spec[:version]

              version_map[[old_spec[:operator], old_spec[:version]]] = new_spec[:version]
            end

            result = source_req.dup
            version_map.each do |(operator, old_version), new_version|
              pattern = /(#{Regexp.escape(operator)}\s*)#{Regexp.escape(old_version)}/
              result = result.sub(pattern, "\\1#{new_version}")
            end
            result
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

          sig { params(old_req: String).returns(Regexp) }
          def declaration_regex(old_req)
            /(?<declaration>["']#{escape}\s*#{extras_pattern}\s*#{Regexp.escape(old_req)}["'])/mi
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
