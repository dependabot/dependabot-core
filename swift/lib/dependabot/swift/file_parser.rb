# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      def parse
        raise NotImplementedError
      end

      private

      def check_required_files
        raise NotImplementedError
      end
    end
  end
end

Dependabot::FileParsers.
  register("swift", Dependabot::Swift::FileParser)
