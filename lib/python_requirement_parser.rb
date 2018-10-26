# frozen_string_literal: true

class PythonRequirementParser
  NAME = /[a-zA-Z0-9\-_\.]+/.freeze
  EXTRA = /[a-zA-Z0-9\-_\.]+/.freeze
  COMPARISON = /===|==|>=|<=|<|>|~=|!=/.freeze
  VERSION = /[0-9]+[a-zA-Z0-9\-_\.*]*(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?/.freeze
  REQUIREMENT =
    /(?<comparison>#{COMPARISON})\s*\\?\s*(?<version>#{VERSION})/.freeze
  HASH = /--hash=(?<algorithm>.*?):(?<hash>.*?)(?=\s|$)/.freeze
  REQUIREMENTS = /#{REQUIREMENT}(\s*,\s*\\?\s*#{REQUIREMENT})*/.freeze
  HASHES = /#{HASH}(\s*\\?\s*#{HASH})*/.freeze

  INSTALL_REQ_WITH_REQUIREMENT =
    /\s*\\?\s*(?<name>#{NAME})
      \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
      \s*\\?\s*(?<requirements>#{REQUIREMENTS})
      \s*\\?\s*(?<hashes>#{HASHES})?
      \s*#*\s*(?<comment>.+)?
    /x.freeze

  INSTALL_REQ_WITHOUT_REQUIREMENT =
    /^\s*\\?\s*(?<name>#{NAME})
      \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
      \s*\\?\s*(?<hashes>#{HASHES})?
      \s*#*\s*(?<comment>.+)?$
    /x.freeze

  NAME_WITH_EXTRAS =
    /\s*\\?\s*(?<name>#{NAME})
      (\s*\\?\s*\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
    /x.freeze
end
