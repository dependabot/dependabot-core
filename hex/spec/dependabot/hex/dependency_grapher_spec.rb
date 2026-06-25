# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex"
require "dependabot/dependency_graphers"

RSpec.describe Dependabot::Hex::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("hex").new(
      file_parser: parser
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: fixture("projects", "graphing_dependencies", "mix.exs")
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("projects", "graphing_dependencies", "mix.lock")
    )
  end

  let(:dependency_files) { [mixfile, lockfile] }

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("hex").new(
      dependency_files: dependency_files,
      source: source
    )
  end

  it "is registered for the hex package manager" do
    expect(Dependabot::DependencyGraphers.for_package_manager("hex"))
      .to eq(described_class)
  end

  describe "#relevant_dependency_file" do
    context "when a mix.lock is present" do
      it "returns the lockfile" do
        expect(grapher.relevant_dependency_file).to eq(lockfile)
      end
    end

    context "when no mix.lock is present" do
      let(:dependency_files) { [mixfile] }

      it "returns the mixfile" do
        expect(grapher.relevant_dependency_file).to eq(mixfile)
      end
    end
  end

  describe "#resolved_dependencies" do
    subject(:resolved) { grapher.resolved_dependencies }

    it "returns the correct number of dependencies" do
      expect(resolved.count).to eq(5)
    end

    it "uses pkg:hex PURLs" do
      expect(resolved.keys).to all(start_with("pkg:hex/"))
    end

    it "includes direct dependencies as direct" do
      plug = resolved["pkg:hex/plug@1.3.5"]
      expect(plug).not_to be_nil
      expect(plug.direct).to be(true)
      expect(plug.runtime).to be(true)

      phoenix = resolved["pkg:hex/phoenix@1.2.5"]
      expect(phoenix).not_to be_nil
      expect(phoenix.direct).to be(true)
      expect(phoenix.runtime).to be(true)
    end

    it "marks transitive dependencies as indirect" do
      mime = resolved["pkg:hex/mime@1.2.0"]
      expect(mime).not_to be_nil
      expect(mime.direct).to be(false)

      phoenix_pubsub = resolved["pkg:hex/phoenix_pubsub@1.0.2"]
      expect(phoenix_pubsub).not_to be_nil
      expect(phoenix_pubsub.direct).to be(false)

      poison = resolved["pkg:hex/poison@2.0.1"]
      expect(poison).not_to be_nil
      expect(poison.direct).to be(false)
    end

    it "correctly assigns subdependencies for plug" do
      plug = resolved["pkg:hex/plug@1.3.5"]
      expect(plug.dependencies).to include("pkg:hex/mime@1.2.0")
    end

    it "correctly assigns subdependencies for phoenix" do
      phoenix = resolved["pkg:hex/phoenix@1.2.5"]
      expect(phoenix.dependencies).to include(
        "pkg:hex/phoenix_pubsub@1.0.2",
        "pkg:hex/plug@1.3.5",
        "pkg:hex/poison@2.0.1"
      )
    end

    it "returns empty dependencies for leaf packages" do
      mime = resolved["pkg:hex/mime@1.2.0"]
      expect(mime.dependencies).to be_empty

      poison = resolved["pkg:hex/poison@2.0.1"]
      expect(poison.dependencies).to be_empty

      phoenix_pubsub = resolved["pkg:hex/phoenix_pubsub@1.0.2"]
      expect(phoenix_pubsub.dependencies).to be_empty
    end
  end
end
