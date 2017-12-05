# frozen_string_literal: true

require "dependabot/file_parsers/java_script/npm"

module Dependabot
  module FileParsers
    module JavaScript
      class Yarn < Dependabot::FileParsers::JavaScript::Npm
      end
    end
  end
end
