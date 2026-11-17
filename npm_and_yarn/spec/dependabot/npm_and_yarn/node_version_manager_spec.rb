# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/node_version_manager"

RSpec.describe Dependabot::NpmAndYarn::NodeVersionManager do
  before do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      "node -v", fingerprint: "node -v"
    ).and_return("v24.15.0\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "list"],
      fingerprint: "nvm ls-remote"
    ).and_return("  v18.20.8 (Latest LTS: Hydrogen)\n  v20.19.5\n  v22.20.0\n  iojs-v3.3.1\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", "20.19.5"],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_return("/home/dependabot/.nvm/versions/node/v20.19.5/bin/node\n")
  end

  it "downloads the highest published version matching the engine range" do
    manager = described_class.new(["^18.0.0 || ^20.0.0"])

    expect(manager.bin_directory).to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
  end

  it "resolves and installs only once per manager" do
    manager = described_class.new(["20.x"])
    2.times { manager.bin_directory }

    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
      .with(["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote").once
  end

  it "retains a compatible default runtime without contacting the release server" do
    expect(described_class.new([">=18"]).bin_directory).to be_nil
    expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      .with(["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote")
  end

  it "honors an exact version rather than selecting another release in its major" do
    expect(described_class.new(["20.19.5"]).bin_directory)
      .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
  end

  it "uses npm semantics for partial and wildcard comparator ranges" do
    {
      "<22" => ["v24.15.0\n", "20.19.5"],
      "<=22" => ["v24.15.0\n", "22.20.0"],
      ">22" => ["v17.0.0\n", "23.0.0"],
      ">=22" => ["v17.0.0\n", "23.0.0"],
      "<=22.1" => ["v24.15.0\n", "22.1.9"],
      ">22.1" => ["v17.0.0\n", "23.0.0"],
      "<22.x" => ["v24.15.0\n", "20.19.5"],
      "<=22.x" => ["v24.15.0\n", "22.20.0"],
      "<=22.X.*" => ["v24.15.0\n", "22.20.0"],
      ">22.x" => ["v22.20.0\n", "23.0.0"],
      ">=22.*" => ["v17.0.0\n", "23.0.0"],
      "<=22.1.x" => ["v24.15.0\n", "22.1.9"],
      ">22.1.* <22.20.0" => ["v17.0.0\n", "22.2.0"],
      "=22.x" => ["v24.15.0\n", "22.20.0"],
      "=22.1.X" => ["v24.15.0\n", "22.1.9"],
      "<20.x || >22.x" => ["v22.20.0\n", "23.0.0"]
    }.each do |requirement, (current_version, expected_version)|
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node -v", fingerprint: "node -v"
      ).and_return(current_version)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        ["bash", "/opt/node-version-manager", "list"],
        fingerprint: "nvm ls-remote"
      ).and_return("  v18.20.8\n  v20.19.5\n  v22.0.0\n  v22.1.9\n  v22.2.0\n  v22.20.0\n  v23.0.0\n")
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        ["bash", "/opt/node-version-manager", "install", expected_version],
        fingerprint: "nvm install <version>",
        stderr_to_stdout: false
      ).and_return("/home/dependabot/.nvm/versions/node/v#{expected_version}/bin/node\n")

      expect(described_class.new([requirement]).bin_directory)
        .to eq("/home/dependabot/.nvm/versions/node/v#{expected_version}/bin"), requirement
    end
  end

  it "honors wildcard-only comparator ranges" do
    %w(>=* <=x =X).each do |requirement|
      expect(described_class.new([requirement]).bin_directory).to be_nil
    end
    %w(>* <x).each do |requirement|
      expect { described_class.new([requirement]).bin_directory }
        .to raise_error(Dependabot::ToolVersionNotSupported)
    end
  end

  it "accepts bare wildcard ranges and wildcard alternatives" do
    ["x", "X", "22.x || X"].each do |requirement|
      expect(described_class.new([requirement]).bin_directory).to be_nil
    end
  end

  it "honors a partial hyphen upper bound ending in zero" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote"
    ).and_return("  v22.0.0\n  v22.0.9\n  v22.1.0\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", "22.0.9"],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_return("/home/dependabot/.nvm/versions/node/v22.0.9/bin/node\n")

    expect(described_class.new(["18 - 22.0", "22.0.x"]).bin_directory)
      .to eq("/home/dependabot/.nvm/versions/node/v22.0.9/bin")

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      "node -v", fingerprint: "node -v"
    ).and_return("v22.0.7\n")
    expect(described_class.new(["18 - 22.0", "22.0.x"]).bin_directory).to be_nil
  end

  it "retains a default runtime that matches a wildcard comparator" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      "node -v", fingerprint: "node -v"
    ).and_return("v22.20.0\n")

    expect(described_class.new(["<=22.x"]).bin_directory).to be_nil
  end

  it "rejects conflicting wildcard comparator requirements" do
    expect { described_class.new([">22.x", "<=22.x"]).bin_directory }
      .to raise_error(Dependabot::ToolVersionNotSupported, />22.x AND <=22.x/)
  end

  it "does not expand a fully specified comparator" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      "node -v", fingerprint: "node -v"
    ).and_return("v22.20.0\n")

    expect(described_class.new([">22.0.0"]).bin_directory).to be_nil
  end

  it "selects Node 18 for the manifest requirement from issue 7426" do
    file = Dependabot::DependencyFile.new(name: "package.json", content: '{"engines":{"node":"18"}}')
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", "18.20.8"],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_return("/home/dependabot/.nvm/versions/node/v18.20.8/bin/node\n")

    requirements, preferred = described_class.requirements_from_file(file)
    expect(described_class.new(requirements, preferred_requirement: preferred).bin_directory)
      .to eq("/home/dependabot/.nvm/versions/node/v18.20.8/bin")
  end

  it "reports a requirement with no published matching version" do
    expect { described_class.new(["99.x"]).bin_directory }
      .to raise_error(Dependabot::ToolVersionNotSupported, /99.x/)
  end

  it "rejects invalid requirements without passing repository content to a shell" do
    expect { described_class.new(["18; touch /tmp/injected"]).bin_directory }
      .to raise_error(Dependabot::MisconfiguredTooling)
    expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      .with(["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote")
  end

  it "does not fall back to an incompatible default when installation fails" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", "20.19.5"],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_raise(
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "Download failed", error_context: {})
    )

    expect { described_class.new(["20.x"]).bin_directory }
      .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /Download failed/)
  end

  it "does not select a runtime satisfying only one of engines and devEngines" do
    expect { described_class.new(["18.x", "20.x"]).bin_directory }
      .to raise_error(Dependabot::ToolVersionNotSupported, /18.x AND 20.x/)
  end

  it "resolves an LTS alias to an exact published version" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "resolve", "lts/iron"],
      fingerprint: "nvm version-remote <alias>"
    ).and_return("v20.19.5\n")

    expect(described_class.new(["lts/iron"]).bin_directory)
      .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
  end

  it "reports an unresolved alias rather than using the default" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "resolve", "lts/unknown"],
      fingerprint: "nvm version-remote <alias>"
    ).and_return("N/A\n")

    expect { described_class.new(["lts/unknown"]).bin_directory }
      .to raise_error(Dependabot::MisconfiguredTooling, %r{lts/unknown})
  end

  it "rejects unexpected installation output instead of selecting the working directory" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", "20.19.5"],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_return("")

    expect { described_class.new(["20.x"]).bin_directory }
      .to raise_error(Dependabot::MisconfiguredTooling, /invalid executable path/)
  end

  describe ".requirements_from_file" do
    it "uses a version file instead of engines.node while retaining devEngines" do
      file = Dependabot::DependencyFile.new(
        name: "package.json",
        content: '{"engines":{"node":"24"},"devEngines":{"runtime":{"name":"node","version":">=20"}}}'
      )
      version_file = Dependabot::DependencyFile.new(name: ".nvmrc", content: "# development\nv20\n")

      requirements, preferred = described_class.requirements_from_file(file, version_file: version_file)
      expect(requirements).to eq(["v20", ">=20"])
      expect(described_class.new(requirements, preferred_requirement: preferred).bin_directory)
        .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
    end

    it "supports a .node-version file with an exact version" do
      file = Dependabot::DependencyFile.new(name: "package.json", content: "{}")
      version_file = Dependabot::DependencyFile.new(name: ".node-version", content: "20.19.5\n")

      requirements, preferred = described_class.requirements_from_file(file, version_file: version_file)
      expect(described_class.new(requirements, preferred_requirement: preferred).bin_directory)
        .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
    end

    it "preserves .nvmrc comparators while ignoring metadata and comments" do
      file = Dependabot::DependencyFile.new(name: "package.json", content: "{}")
      [">=20", "<=22.x", "=20.19.5", ">=20 <=20.x"].each do |range|
        version_file = Dependabot::DependencyFile.new(
          name: ".nvmrc", content: "# development\n key = value\n#{range} # Node version\n"
        )

        expect(described_class.requirements_from_file(file, version_file: version_file)).to eq([[range], nil])
      end

      version_file = Dependabot::DependencyFile.new(name: ".nvmrc", content: ">=20 <=20.x")
      requirements, preferred = described_class.requirements_from_file(file, version_file: version_file)
      expect(described_class.new(requirements, preferred_requirement: preferred).bin_directory)
        .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
    end

    it "rejects a version file that conflicts with blocking devEngines" do
      file = Dependabot::DependencyFile.new(
        name: "package.json", content: '{"devEngines":{"runtime":{"name":"node","version":"18.x"}}}'
      )
      version_file = Dependabot::DependencyFile.new(name: ".nvmrc", content: "20")
      requirements, preferred = described_class.requirements_from_file(file, version_file: version_file)

      expect { described_class.new(requirements, preferred_requirement: preferred).bin_directory }
        .to raise_error(Dependabot::ToolVersionNotSupported, /20 AND 18.x/)
    end

    it "rejects empty or ambiguous version files" do
      file = Dependabot::DependencyFile.new(name: "package.json", content: "{}")
      ["", "key=value\n# comment\n", ">=20\n<=22\n", "20\n22\n"].each do |content|
        version_file = Dependabot::DependencyFile.new(name: ".nvmrc", content: content)
        expect { described_class.requirements_from_file(file, version_file: version_file) }
          .to raise_error(Dependabot::MisconfiguredTooling, /exactly one version/)
      end
      version_file = Dependabot::DependencyFile.new(name: ".node-version", content: " \n")
      expect { described_class.requirements_from_file(file, version_file: version_file) }
        .to raise_error(Dependabot::MisconfiguredTooling, /must contain a version/)
    end

    it "reads devEngines.runtime without engines.node" do
      file = Dependabot::DependencyFile.new(
        name: "package.json", content: '{"devEngines":{"runtime":{"name":"node","version":"26.x"}}}'
      )

      expect(described_class.requirements_from_file(file)).to eq([["26.x"], nil])
    end

    it "keeps both the engine constraint and the array of runtime alternatives" do
      file = Dependabot::DependencyFile.new(
        name: "package.json",
        content: {
          engines: { node: ">=22" },
          devEngines: { runtime: [{ name: "node", version: "24.x" }, { name: "node", version: "26.x" }] }
        }.to_json
      )

      expect(described_class.requirements_from_file(file)).to eq([[">=22", "24.x || 26.x"], nil])
    end

    it "treats warning and ignored runtime requirements as preferences" do
      %w(warn ignore).each do |on_fail|
        file = Dependabot::DependencyFile.new(
          name: "package.json",
          content: { devEngines: { runtime: { name: "node", version: "20.x", onFail: on_fail } } }.to_json
        )
        requirements, preferred = described_class.requirements_from_file(file)

        expect(requirements).to be_empty
        expect(described_class.new(requirements, preferred_requirement: preferred).bin_directory)
          .to eq("/home/dependabot/.nvm/versions/node/v20.19.5/bin")
      end
    end

    it "uses the last runtime alternative's onFail for the preference" do
      file = Dependabot::DependencyFile.new(
        name: "package.json",
        content: {
          devEngines: {
            runtime: [{ name: "node", version: "18.x", onFail: "error" },
                      { name: "node", version: "20.x", onFail: "warn" }]
          }
        }.to_json
      )
      expect(described_class.requirements_from_file(file)).to eq([[], "18.x || 20.x"])
    end

    it "falls back to the required runtime if a preferred range conflicts" do
      manager = described_class.new(["18.x"], preferred_requirement: "20.x")
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        ["bash", "/opt/node-version-manager", "install", "18.20.8"],
        fingerprint: "nvm install <version>",
        stderr_to_stdout: false
      ).and_return("/home/dependabot/.nvm/versions/node/v18.20.8/bin/node\n")

      expect(manager.bin_directory).to eq("/home/dependabot/.nvm/versions/node/v18.20.8/bin")
    end

    it "falls back to a compatible default when a preferred runtime cannot be installed" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        ["bash", "/opt/node-version-manager", "install", "20.19.5"],
        fingerprint: "nvm install <version>",
        stderr_to_stdout: false
      ).and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "Download failed", error_context: {}))
      expect(Dependabot.logger).to receive(:warn).with(/Download failed/)

      expect(described_class.new([">=20"], preferred_requirement: "20.x").bin_directory).to be_nil
    end

    it "falls back to a compatible default when release discovery fails" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        ["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote"
      ).and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "Mirror unavailable", error_context: {})
      )
      expect(Dependabot.logger).to receive(:warn).with(/Mirror unavailable/)

      expect(described_class.new([], preferred_requirement: "20.x").bin_directory).to be_nil
    end

    it "still fails when the required runtime cannot be satisfied" do
      expect { described_class.new(["99.x"], preferred_requirement: "20.x").bin_directory }
        .to raise_error(Dependabot::ToolVersionNotSupported, /99.x/)
    end

    it "falls back when the optional range is invalid" do
      expect(Dependabot.logger).to receive(:warn).with(/Could not satisfy preferred Node.js runtime/)
      expect(described_class.new([], preferred_requirement: "not a range").bin_directory).to be_nil
    end

    it "allows the default runtime when a Node alternative has no version" do
      file = Dependabot::DependencyFile.new(
        name: "package.json",
        content: '{"devEngines":{"runtime":[{"name":"node","version":"26.x"},{"name":"node"}]}}'
      )

      expect(described_class.requirements_from_file(file)).to eq([[], nil])
    end

    it "allows the default runtime when a Node alternative has an empty version range" do
      ["", "  "].each do |version|
        file = Dependabot::DependencyFile.new(
          name: "package.json",
          content: { devEngines: { runtime: [{ name: "node", version: "26.x" }, { name: "node", version: version }] } }
            .to_json
        )

        expect(described_class.requirements_from_file(file)).to eq([[], nil])
      end
    end

    it "rejects a non-string Node runtime version" do
      file = Dependabot::DependencyFile.new(
        name: "package.json", content: '{"devEngines":{"runtime":{"name":"node","version":null}}}'
      )

      expect { described_class.requirements_from_file(file) }
        .to raise_error(Dependabot::MisconfiguredTooling, /version must be a string/)
    end

    it "reports malformed runtime configuration" do
      file = Dependabot::DependencyFile.new(name: "package.json", content: '{"devEngines":{"runtime":"26"}}')

      expect { described_class.requirements_from_file(file) }
        .to raise_error(Dependabot::MisconfiguredTooling, /devEngines.runtime/)
    end
  end
end
