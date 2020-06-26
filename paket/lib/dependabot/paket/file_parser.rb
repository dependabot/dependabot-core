# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Paket
    class FileParser < Dependabot::FileParsers::Base

    end
  end
end

Dependabot::FileParsers.register("paket", Dependabot::Paket::FileParser)
