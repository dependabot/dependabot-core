# typed: true
# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Devcontainers
    class FileParser < Dependabot::FileParsers::Base
      def parse
        []
      end

      private

      def check_required_files; end
    end
  end
end

Dependabot::FileParsers.register("devcontainers", Dependabot::Devcontainers::FileParser)
