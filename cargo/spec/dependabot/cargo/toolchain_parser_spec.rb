# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/cargo/toolchain_parser"

RSpec.describe Dependabot::Cargo::ToolchainParser do
  it "returns sparse-registry for nightlies in a certain range" do
    toolchain = Dependabot::DependencyFile.new(
      name: "rust-toolchain",
      content: "[toolchain]\nchannel = \"nightly-2022-07-10\""
    )
    expect(described_class.new(toolchain).sparse_flag).to eq("-Z sparse-registry")
  end

  it "doesn't return sparse-registry for stable" do
    toolchain = Dependabot::DependencyFile.new(
      name: "rust-toolchain",
      content: "[toolchain]\nchannel = \"stable\""
    )
    expect(described_class.new(toolchain).sparse_flag).to eq("")
  end

  it "doesn't return sparse-registry when no toolchain file" do
    expect(described_class.new(nil).sparse_flag).to eq("")
  end

  it "doesn't return sparse-registry for nightlies outside the range" do
    toolchain = Dependabot::DependencyFile.new(
      name: "rust-toolchain",
      content: "[toolchain]\nchannel = \"nightly-2023-01-21\""
    )
    expect(described_class.new(toolchain).sparse_flag).to eq("")
  end

  it "doesn't return sparse-registry when the channel isn't specified" do
    toolchain = Dependabot::DependencyFile.new(
      name: "rust-toolchain",
      content: "[toolchain]"
    )
    expect(described_class.new(toolchain).sparse_flag).to eq("")
  end
end
