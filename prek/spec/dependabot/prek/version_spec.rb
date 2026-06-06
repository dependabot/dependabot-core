# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/prek/version"

RSpec.describe Dependabot::Prek::Version do
  it "is registered as the version class for the prek package manager" do
    expect(Dependabot::Utils.version_class_for_package_manager("prek")).to eq(described_class)
  end

  it "compares versions like a standard Dependabot version" do
    expect(described_class.new("1.2.3")).to be > described_class.new("1.2.2")
  end
end
