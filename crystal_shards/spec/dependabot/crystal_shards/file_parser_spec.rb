# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::CrystalShards::FileParser do
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/project",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a basic shard.yml" do
      let(:files) { [shard_yml] }
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: fixture("shard.yml")
        )
      end

      it "parses dependencies correctly" do
        expect(dependencies.length).to eq(2)
        expect(dependencies.map(&:name)).to contain_exactly("kemal", "webmock")
      end

      describe "the first dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "kemal" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("kemal")
          expect(dependency.requirements).to eq(
            [{
              requirement: "~> 1.0.0",
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/kemalcr/kemal",
                branch: nil,
                ref: nil
              },
              file: "shard.yml"
            }]
          )
        end
      end

      describe "the development dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "webmock" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("webmock")
          expect(dependency.requirements.first[:groups]).to eq(["development_dependencies"])
        end
      end
    end

    context "with shard.yml and shard.lock" do
      let(:files) { [shard_yml, shard_lock] }
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: fixture("shard.yml")
        )
      end
      let(:shard_lock) do
        Dependabot::DependencyFile.new(
          name: "shard.lock",
          content: fixture("shard.lock")
        )
      end

      it "uses locked versions" do
        kemal = dependencies.find { |d| d.name == "kemal" }
        expect(kemal.version).to eq("1.0.0")
      end
    end

    context "with git source" do
      let(:files) { [shard_yml] }
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: fixture("shard_with_git.yml")
        )
      end

      it "parses git source dependencies" do
        radix = dependencies.find { |d| d.name == "radix" }
        expect(radix).to be_a(Dependabot::Dependency)
        expect(radix.requirements.first[:source]).to eq(
          {
            type: "git",
            url: "https://github.com/luislavena/radix.git",
            branch: "master",
            ref: nil
          }
        )
      end

      it "parses tag references" do
        webmock = dependencies.find { |d| d.name == "webmock" }
        expect(webmock.requirements.first[:source][:ref]).to eq("v0.14.0")
      end
    end

    context "with malformed YAML" do
      let(:files) { [shard_yml] }
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: "invalid: yaml: content:"
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with no dependencies" do
      let(:files) { [shard_yml] }
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: <<~YAML
            name: my_shard
            version: 1.0.0
          YAML
        )
      end

      it "returns an empty array" do
        expect(dependencies).to eq([])
      end
    end
  end

  describe "#ecosystem" do
    let(:files) { [shard_yml] }
    let(:shard_yml) do
      Dependabot::DependencyFile.new(
        name: "shard.yml",
        content: fixture("shard.yml")
      )
    end

    it "returns the ecosystem with package manager info" do
      ecosystem = parser.ecosystem
      expect(ecosystem.name).to eq("crystal_shards")
      expect(ecosystem.package_manager.name).to eq("shards")
    end
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", name))
  end
end
