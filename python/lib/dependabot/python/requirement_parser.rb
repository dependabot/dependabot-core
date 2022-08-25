# frozen_string_literal: true

module Dependabot
  module Python
    class RequirementParser
      NAME = /[a-zA-Z0-9](?:[a-zA-Z0-9\-_\.]*[a-zA-Z0-9])?/.freeze
      EXTRA = /[a-zA-Z0-9\-_\.]+/.freeze
      COMPARISON = /===|==|>=|<=|<|>|~=|!=/.freeze
      VERSION = /([1-9][0-9]*!)?[0-9]+[a-zA-Z0-9\-_.*]*(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?/.
                freeze
      REQUIREMENT =
        /(?<comparison>#{COMPARISON})\s*\\?\s*(?<version>#{VERSION})/.freeze
      HASH = /--hash=(?<algorithm>.*?):(?<hash>.*?)(?=\s|$)/.freeze
      REQUIREMENTS = /#{REQUIREMENT}(\s*,\s*\\?\s*#{REQUIREMENT})*/.freeze
      HASHES = /#{HASH}(\s*\\?\s*#{HASH})*/.freeze
      MARKER_OP = /\s*(#{COMPARISON}|(\s*in)|(\s*not\s*in))/.freeze
      PYTHON_STR_C =
        %r{[a-zA-Z0-9\s\(\)\.\{\}\-_\*#:;/\?\[\]!~`@\$%\^&=\+\|<>]}.freeze
      PYTHON_STR = /('(#{PYTHON_STR_C}|")*'|"(#{PYTHON_STR_C}|')*")/.freeze
      ENV_VAR =
        /python_version|python_full_version|os_name|sys_platform|
         platform_release|platform_system|platform_version|platform_machine|
         platform_python_implementation|implementation_name|
         implementation_version/.freeze
      MARKER_VAR = /\s*(#{ENV_VAR}|#{PYTHON_STR})/.freeze
      MARKER_EXPR_ONE = /#{MARKER_VAR}#{MARKER_OP}#{MARKER_VAR}/.freeze
      MARKER_EXPR =
        /(#{MARKER_EXPR_ONE}|\(\s*|\s*\)|\s+and\s+|\s+or\s+)+/.freeze

      INSTALL_REQ_WITH_REQUIREMENT =
        /\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?
        /x.freeze

      INSTALL_REQ_WITHOUT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?$
        /x.freeze

      VALID_REQ_TXT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})?\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*(\#+\s*(?<comment>.*))?$
        /x.freeze

      NAME_WITH_EXTRAS =
        /\s*\\?\s*(?<name>#{NAME})
          (\s*\\?\s*\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
        /x.freeze
    end
  end
end
