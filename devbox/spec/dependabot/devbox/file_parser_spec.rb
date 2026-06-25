# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_parsers"
require "dependabot/devbox/file_parser"

# Behaviour is exercised in later phases; for now this just asserts the class
# is wired into the file-parser registry.
RSpec.describe Dependabot::Devbox::FileParser do
  it "is registered for the devbox package manager" do
    expect(Dependabot::FileParsers.for_package_manager("devbox")).to eq(described_class)
  end
end
