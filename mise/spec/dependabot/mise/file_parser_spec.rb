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
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false))
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
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump({}))
      end

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "when mise ls returns invalid JSON" do
      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false))
          .and_return("{")
      end

      it "returns no dependencies" do
        expect(dependencies).to eq([])
      end
    end

    context "with mixed version formats" do
      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false))
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

    context "with multiple mise config files" do
      let(:dependency_files) { [mise_toml, mise_production_toml] }

      let(:mise_production_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.production.toml",
          content: <<~TOML
            [tools]
            erlang = "28.0.0"
            python = "3.11.0"
          TOML
        )
      end

      before do
        # Allow File.write for any file
        allow(File).to receive(:write)

        # Mock mise ls to return different results for each file
        call_count = 0
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false)) do
          call_count += 1
          if call_count == 1
            # First call for mise.toml
            JSON.dump(
              "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }],
              "elixir" => [{ "requested_version" => "1.18.4-otp-27", "version" => "1.18.4-otp-27" }],
              "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }]
            )
          else
            # Second call for mise.production.toml
            JSON.dump(
              "erlang" => [{ "requested_version" => "28.0.0", "version" => "28.0.0" }],
              "python" => [{ "requested_version" => "3.11.0", "version" => "3.11.0" }]
            )
          end
        end
      end

      it "creates one dependency per tool name" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "erlang",
          "elixir",
          "helm",
          "python"
        )
      end

      it "tracks requirements from multiple files for the same tool" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.requirements.length).to eq(2)

        files = erlang.requirements.map { |r| r[:file] }
        expect(files).to contain_exactly("mise.toml", "mise.production.toml")
      end

      it "uses the lowest version across all files to detect updates needed" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.version).to eq("27.3.2")
      end

      it "stores the correct requirement for each file" do
        erlang = dependencies.find { |d| d.name == "erlang" }

        mise_toml_req = erlang.requirements.find { |r| r[:file] == "mise.toml" }
        expect(mise_toml_req[:requirement]).to eq("27.3.2")

        production_req = erlang.requirements.find { |r| r[:file] == "mise.production.toml" }
        expect(production_req[:requirement]).to eq("28.0.0")
      end

      it "creates separate dependencies for tools that only exist in one file" do
        elixir = dependencies.find { |d| d.name == "elixir" }
        expect(elixir.requirements.length).to eq(1)
        expect(elixir.requirements.first[:file]).to eq("mise.toml")

        python = dependencies.find { |d| d.name == "python" }
        expect(python.requirements.length).to eq(1)
        expect(python.requirements.first[:file]).to eq("mise.production.toml")
      end
    end

    context "with .mise.toml dotfile" do
      let(:dependency_files) { [dotfile_mise_toml] }

      let(:dotfile_mise_toml) do
        Dependabot::DependencyFile.new(
          name: ".mise.toml",
          content: <<~TOML
            [tools]
            node = "20.0.0"
          TOML
        )
      end

      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(
                        "node" => [{ "requested_version" => "20.0.0", "version" => "20.0.0" }]
                      ))
      end

      it "parses dotfile mise config" do
        expect(dependencies.map(&:name)).to contain_exactly("node")
        expect(dependencies.first.requirements.first[:file]).to eq(".mise.toml")
      end
    end

    context "with environment-specific config files" do
      let(:dependency_files) { [mise_toml, mise_dev_toml, mise_local_toml] }

      let(:mise_dev_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.dev.toml",
          content: <<~TOML
            [tools]
            erlang = "27.0.0"
          TOML
        )
      end

      let(:mise_local_toml) do
        Dependabot::DependencyFile.new(
          name: ".mise.local.toml",
          content: <<~TOML
            [tools]
            erlang = "26.0.0"
          TOML
        )
      end

      before do
        # Allow File.write for any file
        allow(File).to receive(:write)

        # Mock mise ls to return different results for each file
        call_count = 0
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false)) do
          call_count += 1
          case call_count
          when 1
            JSON.dump("erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }])
          when 2
            JSON.dump("erlang" => [{ "requested_version" => "27.0.0", "version" => "27.0.0" }])
          when 3
            JSON.dump("erlang" => [{ "requested_version" => "26.0.0", "version" => "26.0.0" }])
          end
        end
      end

      it "tracks erlang across all three files" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.requirements.length).to eq(3)

        files = erlang.requirements.map { |r| r[:file] }
        expect(files).to contain_exactly("mise.toml", "mise.dev.toml", ".mise.local.toml")
      end

      it "uses the lowest version (26.0.0) to ensure updates are detected" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.version).to eq("26.0.0")
      end
    end

    context "when one file is already on latest version" do
      let(:dependency_files) { [mise_toml, mise_production_toml] }

      let(:mise_production_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.production.toml",
          content: <<~TOML
            [tools]
            erlang = "27.0.0"
          TOML
        )
      end

      before do
        # Allow File.write for any file
        allow(File).to receive(:write)

        # Mock mise ls to return different results for each file
        call_count = 0
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("mise ls --current --local --json", hash_including(stderr_to_stdout: false)) do
          call_count += 1
          if call_count == 1
            # First call - mise.toml with latest version
            JSON.dump(
              "erlang" => [{ "requested_version" => "28.0.0", "version" => "28.0.0" }]
            )
          else
            # Second call - mise.production.toml with older version
            JSON.dump(
              "erlang" => [{ "requested_version" => "27.0.0", "version" => "27.0.0" }]
            )
          end
        end
      end

      it "uses the lowest version to ensure update is still detected" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.version).to eq("27.0.0")
      end

      it "tracks both file requirements" do
        erlang = dependencies.find { |d| d.name == "erlang" }
        expect(erlang.requirements.length).to eq(2)

        files = erlang.requirements.map { |r| r[:file] }
        expect(files).to contain_exactly("mise.toml", "mise.production.toml")
      end

      it "stores correct versions for each file" do
        erlang = dependencies.find { |d| d.name == "erlang" }

        mise_toml_req = erlang.requirements.find { |r| r[:file] == "mise.toml" }
        expect(mise_toml_req[:requirement]).to eq("28.0.0")

        production_req = erlang.requirements.find { |r| r[:file] == "mise.production.toml" }
        expect(production_req[:requirement]).to eq("27.0.0")
      end
    end
  end
end
