# frozen_string_literal: true

class PythonRequirementLineParser
  NAME = /[a-zA-Z0-9\-_\.]+/
  EXTRA = /[a-zA-Z0-9\-_\.]+/
  COMPARISON = /===|==|>=|<=|<|>|~=|!=/
  VERSION = /[a-zA-Z0-9\-_\.]+/
  REQUIREMENT = /(?<comparison>#{COMPARISON})\s*(?<version>#{VERSION})/

  REQUIREMENT_LINE =
    /^\s*(?<name>#{NAME})
      \s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
      \s*(?<requirements>#{REQUIREMENT}(\s*,\s*#{REQUIREMENT})*)?
      \s*#*\s*(?<comment>.+)?$
    /x

  def self.parse(line)
    requirement = line.chomp.match(REQUIREMENT_LINE)
    return if requirement.nil?

    requirements =
      requirement[:requirements].to_s.
      to_enum(:scan, REQUIREMENT).
      map do
        {
          comparison: Regexp.last_match[:comparison],
          version: Regexp.last_match[:version]
        }
      end

    {
      name: requirement[:name],
      requirements: requirements
    }
  end
end
