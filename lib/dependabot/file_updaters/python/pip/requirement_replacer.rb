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
          end

          def updated_content
            updated_content = content.gsub(
              original_declaration_replacement_regex,
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
            matches = []

            dec =
              if old_req.nil?
                regex = PythonRequirementParser::INSTALL_REQ_WITHOUT_REQUIREMENT
                content.scan(regex) { matches << Regexp.last_match }
                matches.find { |m| normalise(m[:name]) == dependency_name }
              else
                regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
                content.scan(regex) { matches << Regexp.last_match }
                matches.
                  select { |m| normalise(m[:name]) == dependency_name }.
                  find { |m| requirements_match(m[:requirements], old_req) }
              end

            raise "Declaration not found for #{dependency_name}!" unless dec
            dec.to_s.strip
          end

          def updated_dependency_declaration_string(old_req, new_req)
            if old_req
              original_dependency_declaration_string(old_req).
                sub(PythonRequirementParser::REQUIREMENTS, new_req)
            else
              original_dependency_declaration_string(old_req).
                sub(PythonRequirementParser::NAME_WITH_EXTRAS) do |nm|
                  nm + new_req
                end
            end
          end

          def original_declaration_replacement_regex
            original_string =
              original_dependency_declaration_string(old_requirement)
            /(?<![\-\w])#{Regexp.escape(original_string)}(?![\-\w])/
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
