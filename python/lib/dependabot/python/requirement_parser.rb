# frozen_string_literal: true

module Dependabot
  module Python
    class RequirementParser
      NAME = /[a-zA-Z0-9](?:[a-zA-Z0-9\-_\.]*[a-zA-Z0-9])?/
      EXTRA = /[a-zA-Z0-9\-_\.]+/
      COMPARISON = /===|==|>=|<=|<|>|~=|!=/
      VERSION = /([1-9][0-9]*!)?[0-9]+[a-zA-Z0-9\-_.*]*(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?/

      REQUIREMENT = /(?<comparison>#{COMPARISON})\s*\\?\s*(?<version>#{VERSION})/
      HASH = /--hash=(?<algorithm>.*?):(?<hash>.*?)(?=\s|$)/
      REQUIREMENTS = /#{REQUIREMENT}(\s*,\s*\\?\s*#{REQUIREMENT})*/
      HASHES = /#{HASH}(\s*\\?\s*#{HASH})*/
      MARKER_OP = /\s*(#{COMPARISON}|(\s*in)|(\s*not\s*in))/
      PYTHON_STR_C = %r{[a-zA-Z0-9\s\(\)\.\{\}\-_\*#:;/\?\[\]!~`@\$%\^&=\+\|<>]}
      PYTHON_STR = /('(#{PYTHON_STR_C}|")*'|"(#{PYTHON_STR_C}|')*")/
      ENV_VAR =
        /python_version|python_full_version|os_name|sys_platform|
         platform_release|platform_system|platform_version|platform_machine|
         platform_python_implementation|implementation_name|
         implementation_version/
      MARKER_VAR = /\s*(#{ENV_VAR}|#{PYTHON_STR})/
      MARKER_EXPR_ONE = /#{MARKER_VAR}#{MARKER_OP}#{MARKER_VAR}/
      MARKER_EXPR = /(#{MARKER_EXPR_ONE}|\(\s*|\s*\)|\s+and\s+|\s+or\s+)+/

      INSTALL_REQ_WITH_REQUIREMENT =
        /\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?
        /x

      INSTALL_REQ_WITHOUT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?$
        /x

      VALID_REQ_TXT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})?\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*(\#+\s*(?<comment>.*))?$
        /x

      NAME_WITH_EXTRAS =
        /\s*\\?\s*(?<name>#{NAME})
          (\s*\\?\s*\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
        /x
    end
  end
end
