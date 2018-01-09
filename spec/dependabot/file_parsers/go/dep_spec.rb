# frozen_string_literal: true

require "dependabot/file_parsers/go/dep"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Go::Dep do
  it_behaves_like "a dependency file parser"
end
