# frozen_string_literal: true

require "dependabot/file_parsers/c_sharp/nuget"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::CSharp::Nuget do
  it_behaves_like "a dependency file parser"
end
