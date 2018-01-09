# frozen_string_literal: true

require "dependabot/file_parsers/dotnet/nuget"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Dotnet::Nuget do
  it_behaves_like "a dependency file parser"
end
