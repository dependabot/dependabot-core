# frozen_string_literal: true

require "python_requirement_parser"
require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class RequirementReplacer
          attr_reader :content, :dependency_name, :old_requirement,
                      :new_requirement

          def initialize(content:, dependency_name:, old_requirement:,
                         new_requirement:)
            @content         = content
            @dependency_name = dependency_name
            @old_requirement = old_requirement
            @new_requirement = new_requirement

            raise "Nil requirements can't be updated" if old_requirement.nil?
          end

          def updated_content
            updated_content = content.gsub(
              original_dependency_declaration_string(old_requirement),
              updated_dependency_declaration_string(
                old_requirement,
                new_requirement
              )
            )

            raise "Expected content to change!" if content == updated_content
            updated_content
          end

          private

          def original_dependency_declaration_string(old_req)
            regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
            matches = []

            content.scan(regex) { matches << Regexp.last_match }
            dec = matches.
                  select { |m| normalise(m[:name]) == dependency_name }.
                  find { |m| requirements_match(m[:requirements], old_req) }
            raise "Declaration not found for #{dependency_name}!" unless dec
            dec.to_s
          end

          def updated_dependency_declaration_string(old_req, new_req)
            original_dependency_declaration_string(old_req).
              sub(PythonRequirementParser::REQUIREMENTS, new_req)
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end

          def requirements_match(req1, req2)
            req1&.split(",")&.map(&:strip)&.sort ==
              req2&.split(",")&.map(&:strip)&.sort
          end
        end
      end
    end
  end
end
