# typed: false
# frozen_string_literal: true

require "dependabot/local_scanner/version"
require "dependabot/local_scanner/local_scanner"

module Dependabot
  module LocalScanner
    class Error < StandardError; end
  end
end
