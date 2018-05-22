# frozen_string_literal: true

class PythonRequirementParser
  NAME = /[a-zA-Z0-9\-_\.]+/
  EXTRA = /[a-zA-Z0-9\-_\.]+/
  COMPARISON = /===|==|>=|<=|<|>|~=|!=/
  VERSION = /[0-9]+[a-zA-Z0-9\-_\.*]*(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?/
  REQUIREMENT = /(?<comparison>#{COMPARISON})\s*\\?\s*(?<version>#{VERSION})/
  HASH = /--hash=(?<algorithm>.*?):(?<hash>.*?)(?=\s|$)/
  REQUIREMENTS = /#{REQUIREMENT}(\s*,\s*\\?\s*#{REQUIREMENT})*/
  HASHES = /#{HASH}(\s*\\?\s*#{HASH})*/

  INSTALL_REQ_WITH_REQUIREMENT =
    /\s*\\?\s*(?<name>#{NAME})
      \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
      \s*\\?\s*(?<requirements>#{REQUIREMENTS})
      \s*\\?\s*(?<hashes>#{HASHES})?
      \s*#*\s*(?<comment>.+)?
    /x

  INSTALL_REQ_WITHOUT_REQUIREMENT =
    /^\s*\\?\s*(?<name>#{NAME})
      \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
      \s*\\?\s*(?<hashes>#{HASHES})?
      \s*#*\s*(?<comment>.+)?$
    /x

  NAME_WITH_EXTRAS =
    /\s*\\?\s*(?<name>#{NAME})
      (\s*\\?\s*\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
    /x
end
