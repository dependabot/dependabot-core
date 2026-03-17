# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/mise/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Mise::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/mise-project",
      directory: "/"
    )
  end

  let(:dependency_files) { [mise_toml] }

  let(:mise_toml) do
    Dependabot::DependencyFile.new(
      name: "mise.toml",
      content: fixture("mise_toml/simple.toml")
    )
  end

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with simple exact versions" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/mise ls/, hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(
                        {
                          "erlang" => [{ "requested_version" => "27.3.2",        "version" => "27.3.2" }],
                          "elixir" => [{ "requested_version" => "1.18.4-otp-27", "version" => "1.18.4-otp-27" }],
                          "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }]
                        }
                      ))
      end

      it "parses tool names correctly" do
        expect(dependencies.map(&:name)).to contain_exactly("erlang", "elixir", "helm")
      end

      it "parses versions correctly" do
        versions = dependencies.to_h { |d| [d.name, d.version] }
        expect(versions).to eq(
          "erlang" => "27.3.2",
          "elixir" => "1.18.4-otp-27",
          "helm" => "3.17.3"
        )
      end
    end

    context "with no tools section" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: fixture("mise_toml/no_tools.toml")
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/mise ls/, hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump({}))
      end

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "when mise ls returns invalid JSON" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/mise ls/, hash_including(stderr_to_stdout: false))
          .and_return("{")
      end

      it "returns no dependencies" do
        expect(dependencies).to eq([])
      end
    end

    context "with mixed version formats" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/mise ls/, hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(
                        {
                          "node" => [{ "requested_version" => "20",     "version" => "20.20.2" }],
                          "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }],
                          "npm:@redocly/cli" => [{ "requested_version" => "2.19.1", "version" => "2.19.1" }],
                          "python" => [{ "requested_version" => "latest", "version" => "3.14.3" }],
                          "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }],
                          "ruby" => [{ "requested_version" => "3.3.0",  "version" => "3.3.0" }],
                          "go" => [{ "requested_version" => "1.18", "version" => "1.18" }]
                        }
                      ))
      end

      it "returns only tools with parseable version strings" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "erlang",
          "helm",
          "npm:@redocly/cli",
          "node",
          "ruby",
          "go"
        )
      end

      it "skips tools pinned to fuzzy aliases like 'latest'" do
        expect(dependencies.map(&:name)).not_to include("python")
      end

      it "uses the resolved version and keeps the partial pin as the requirement" do
        node = dependencies.find { |d| d.name == "node" }
        expect(node.version).to eq("20.20.2")
        expect(node.requirements.first[:requirement]).to eq("20")
      end
    end
  end
end
