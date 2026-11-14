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
        responses = {
          "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }],
          "elixir" => [{ "requested_version" => "1.18.4-otp-27", "version" => "1.18.4-otp-27" }],
          "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }]
        }
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(responses))
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

      it "returns no dependencies" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
        expect(dependencies).to be_empty
      end
    end

    context "when mise ls returns invalid JSON" do
      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_return("{")
      end

      it "reports the manifest as unparseable" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_name).to eq("mise.toml")
        end
      end
    end

    context "when mise cannot list a manifest" do
      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "mise ERROR failed to load mise.toml",
                       error_context: {}
                     ))
      end

      it "reports the manifest as unparseable" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_name).to eq("mise.toml")
          expect(error.message).to include("failed to load mise.toml")
        end
      end
    end

    context "when mise cannot list one of the tools" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: "[tools]\nnode = '20.0.0'\nmissing-tool-xyz = '1.0.0'\n"
        )
      end

      before do
        allow(File).to receive(:write)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump("node" => [{ "requested_version" => "20.0.0", "version" => "20.0.0" }]))
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json", "--", "missing-tool-xyz"],
                hash_including(stderr_to_stdout: false))
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "missing-tool-xyz not found in mise tool registry",
                       error_context: {}
                     ))
      end

      it "skips that tool and keeps the others" do
        expect(dependencies.map { |dep| [dep.name, dep.version] }).to eq([["node", "20.0.0"]])
      end
    end

    context "when invoking the mise CLI" do
      %w(
        mise.toml
        .mise.toml
        mise.production.toml
        .mise.dev.toml
        mise.local.toml
        .mise.local.toml
        mise.my-env.toml
        .mise.my_env.toml
        mise.production.local.toml
        .mise.dev.local.toml
        .config/mise.toml
        .config/mise.local.toml
        .config/mise.production.toml
        .config/mise.production.local.toml
        .config/mise/mise.toml
        .config/mise/mise.local.toml
        .config/mise/config.toml
        .config/mise/config.local.toml
        .config/mise/config.production.toml
        .config/mise/config.production.local.toml
        .mise/config.toml
        .mise/config.local.toml
        .mise/config.dev.toml
        .mise/config.dev.local.toml
        mise/config.toml
        mise/config.local.toml
        mise/config.my-env.toml
        mise/config.my-env.local.toml
        .config/mise/conf.d/tools.toml
        .mise/conf.d/00-node.toml
        mise/conf.d/tools.dev.local.toml
        mise/conf.d/node/mise.toml
        .config/mise/conf.d/git/mise.local.toml
        .mise/conf.d/tools/mise.dev.toml
      ).each do |filename|
        context "with #{filename}" do
          let(:dependency_files) do
            [Dependabot::DependencyFile.new(name: filename, content: "[tools]\nnode = '20.0.0'\n")]
          end

          it "reads the dependency and preserves its manifest filename" do
            expect(dependencies.map { |dep| [dep.name, dep.version, dep.requirements.first[:file]] })
              .to eq([["node", "20.0.0", filename]])
          end
        end
      end

      context "with multiple manifest files" do
        let(:versions_by_file) do
          {
            "mise.toml" => "22.0.0",
            "mise.production.toml" => "20.0.0",
            ".mise.dev.toml" => "18.0.0"
          }
        end
        let(:dependency_files) do
          versions_by_file.map do |filename, version|
            Dependabot::DependencyFile.new(name: filename, content: "[tools]\nnode = '#{version}'\n")
          end
        end

        it "keeps the declared version from each file" do
          expect(dependencies.fetch(0).requirements.to_h { |req| [req[:file], req[:requirement]] })
            .to eq(versions_by_file)
        end

        it "compares updates against the lowest version" do
          expect(dependencies.map { |dep| [dep.name, dep.version] }).to eq([["node", "18.0.0"]])
        end
      end

      context "with a registry alias, a renamed alias and an unknown tool" do
        let(:dependency_files) do
          [Dependabot::DependencyFile.new(
            name: "mise.toml",
            content: "[tools]\nnode = '20.0.0'\nop = '2.30.0'\ngolang = '1.18'\nmissing-tool-xyz = '1.0.0'\n"
          )]
        end

        it "reads every tool mise can resolve under its manifest key" do
          expect(dependencies.map { |dep| [dep.name, dep.version] })
            .to eq([["node", "20.0.0"], ["op", "2.30.0"], ["golang", "1.18"]])
        end
      end

      context "with a config template that runs a command" do
        let(:marker_dir) { Dir.mktmpdir }
        let(:marker) { File.join(marker_dir, "marker") }
        let(:dependency_files) do
          [Dependabot::DependencyFile.new(
            name: "mise.toml",
            content: "[env]\nPROBE = \"{{ exec(command='touch #{marker}') }}\"\n[tools]\nnode = '20.0.0'\n"
          )]
        end

        after { FileUtils.remove_entry(marker_dir) }

        it "reads the tools without running the command" do
          expect(dependencies.map { |dep| [dep.name, dep.version] }).to eq([["node", "20.0.0"]])
          expect(File).not_to exist(marker)
        end
      end

      manifest_orders = [%w(valid templated), %w(templated valid)]
      {
        "a function in the version" => "python = \"{{ get_env(name='PY_VERSION', default='3.12.0') }}\"",
        "an environment variable in the version" => "python = \"{{ env.PY_VERSION }}\"",
        "a literal template in the version" => "python = \"{{ '3.12.0' }}\"",
        "a template in a version table" => "python = { version = \"{{ env.PY_VERSION }}\" }",
        "a template in tool options" =>
          "python = { version = '3.12.0', install_env = { CC = \"{{ get_env(name='CC', default='cc') }}\" } }"
      }.each do |description, declaration|
        context "with #{description} next to a valid manifest" do
          let(:valid) { Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nnode = '20.0.0'\n") }
          let(:templated) do
            Dependabot::DependencyFile.new(name: "mise.dev.toml", content: "[tools]\n#{declaration}\n")
          end

          manifest_orders.each do |order|
            context "when the #{order.first} manifest comes first" do
              let(:dependency_files) { order.map { |name| public_send(name) } }

              it "skips the templated manifest and keeps the other dependencies" do
                expect(dependencies.map { |dep| [dep.name, dep.version, dep.requirements.map(&:file)] })
                  .to eq([["node", "20.0.0", ["mise.toml"]]])
              end
            end
          end
        end
      end
    end

    context "with mixed version formats" do
      let(:mise_toml) do
        Dependabot::DependencyFile.new(
          name: "mise.toml",
          content: <<~TOML
            [tools]
            node = "20"
            erlang = "27.3.2"
            "npm:@redocly/cli" = "2.19.1"
            python = "latest"
            helm = "3.17.3"
            ruby = "3.3.0"
            [tools.golang]
            version = "1.18"
          TOML
        )
      end

      before do
        allow(File).to receive(:write)
        listing = {
          "node" => [{ "requested_version" => "20", "version" => "20.20.2" }],
          "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }],
          "npm:@redocly/cli" => [{ "requested_version" => "2.19.1", "version" => "2.19.1" }],
          "python" => [{ "requested_version" => "latest", "version" => "3.14.3" }],
          "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }],
          "ruby" => [{ "requested_version" => "3.3.0", "version" => "3.3.0" }],
          "go" => [{ "requested_version" => "1.18", "version" => "1.18" }]
        }
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(listing))
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json", "--", "golang"],
                hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump(listing.fetch("go")))
      end

      it "returns only tools with parseable version strings" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "erlang",
          "helm",
          "npm:@redocly/cli",
          "node",
          "ruby",
          "golang"
        )
      end

      it "skips tools pinned to fuzzy aliases like 'latest'" do
        expect(dependencies.map(&:name)).not_to include("python")
      end

      it "uses the resolved version and keeps the partial pin as the requirement" do
        node = dependencies.find { |d| d.name == "node" }
        expect(node.version).to eq("20.20.2")
        expect(node.requirements.first[:requirement]).to eq("20")
        expect(node.requirements.first.metadata_string("resolved_version")).to eq("20.20.2")
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
        allow(File).to receive(:write)

        responses = {
          "mise.toml" => {
            "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }],
            "elixir" => [{ "requested_version" => "1.18.4-otp-27", "version" => "1.18.4-otp-27" }],
            "helm" => [{ "requested_version" => "3.17.3", "version" => "3.17.3" }]
          },
          "mise.production.toml" => {
            "erlang" => [{ "requested_version" => "28.0.0", "version" => "28.0.0" }],
            "python" => [{ "requested_version" => "3.11.0", "version" => "3.11.0" }]
          }
        }
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"],
                hash_including(stderr_to_stdout: false)) do |_, env:, **|
          JSON.dump(responses.fetch(env.fetch("MISE_OVERRIDE_CONFIG_FILENAMES")))
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
          .with(["mise", "ls", "--current", "--no-global", "--json"], hash_including(stderr_to_stdout: false))
          .and_return(JSON.dump("node" => [{ "requested_version" => "20.0.0", "version" => "20.0.0" }]))
      end

      it "parses dotfile mise config" do
        expect(dependencies.map(&:name)).to contain_exactly("node")
        expect(dependencies.first.requirements.first[:file]).to eq(".mise.toml")
      end
    end

    context "with environment-specific config files" do
      let(:dependency_files) { [mise_toml, mise_dev_toml, mise_local_toml] }

      let(:mise_toml) do
        Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = '27.3.2'\n")
      end

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
        allow(File).to receive(:write)

        responses = {
          "mise.toml" => { "erlang" => [{ "requested_version" => "27.3.2", "version" => "27.3.2" }] },
          "mise.dev.toml" => { "erlang" => [{ "requested_version" => "27.0.0", "version" => "27.0.0" }] },
          ".mise.local.toml" => { "erlang" => [{ "requested_version" => "26.0.0", "version" => "26.0.0" }] }
        }
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"],
                hash_including(stderr_to_stdout: false)) do |_, env:, **|
          JSON.dump(responses.fetch(env.fetch("MISE_OVERRIDE_CONFIG_FILENAMES")))
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

      let(:mise_toml) do
        Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = '28.0.0'\n")
      end

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
        allow(File).to receive(:write)

        responses = {
          "mise.toml" => { "erlang" => [{ "requested_version" => "28.0.0", "version" => "28.0.0" }] },
          "mise.production.toml" => { "erlang" => [{ "requested_version" => "27.0.0", "version" => "27.0.0" }] }
        }
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "ls", "--current", "--no-global", "--json"],
                hash_including(stderr_to_stdout: false)) do |_, env:, **|
          JSON.dump(responses.fetch(env.fetch("MISE_OVERRIDE_CONFIG_FILENAMES")))
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
