# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::NpmAndYarn::Helpers do
  describe "::dependencies_with_all_versions_metadata" do
    let(:foo_a) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.1",
        requirements: [{
          requirement: "^0.0.1",
          file: "package.json",
          groups: nil,
          source: nil
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:foo_b) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.2",
        requirements: [{
          requirement: "^0.0.1",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:foo_c) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.3",
        requirements: [{
          requirement: "^0.0.3",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_a) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.1",
        requirements: [{
          requirement: "^0.2.1",
          file: "package.json",
          groups: ["dependencies"],
          source: nil
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_b) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.2",
        requirements: [{
          requirement: "^0.2.1",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_c) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.3",
        requirements: [{
          requirement: "^0.2.3",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    context "when dependencies in set already have :all_versions metadata" do
      it "returns flattened list of dependencies populated with :all_versions metadata" do
        dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
        dependency_set << foo_a << bar_a << foo_c << bar_c << foo_b << bar_b

        expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq([
          Dependabot::Dependency.new(
            name: "foo",
            version: "0.0.1",
            requirements: (foo_a.requirements + foo_c.requirements + foo_b.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [foo_a, foo_c, foo_b] }
          ),
          Dependabot::Dependency.new(
            name: "bar",
            version: "0.2.1",
            requirements: (bar_a.requirements + bar_c.requirements + bar_b.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [bar_a, bar_c, bar_b] }
          )
        ])
      end

      it "correctly merges existing metadata into new metadata" do
        dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
        dependency_set << foo_a
        dependency_set << Dependabot::Dependency.new(
          name: "foo",
          version: "0.0.3",
          requirements: (foo_c.requirements + foo_b.requirements).uniq,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [foo_c, foo_b] }
        )
        dependency_set << bar_c
        dependency_set << bar_b
        dependency_set << Dependabot::Dependency.new(
          name: "bar",
          version: "0.2.1",
          requirements: bar_a.requirements,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [bar_a] }
        )

        expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq([
          Dependabot::Dependency.new(
            name: "foo",
            version: "0.0.1",
            requirements: (foo_a.requirements + foo_c.requirements + foo_b.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [foo_a, foo_c, foo_b] }
          ),
          Dependabot::Dependency.new(
            name: "bar",
            version: "0.2.1",
            requirements: (bar_c.requirements + bar_b.requirements + bar_a.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [bar_c, bar_b, bar_a] }
          )
        ])
      end
    end
  end

  describe "::package_manager_install" do
    it "runs the correct corepack install command" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("7.0.0/n")
      expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "corepack install npm@7.0.0 --global --cache-only",
        fingerprint: "corepack install <name>@<version> --global --cache-only",
        env: {}
      )
      described_class.package_manager_install("npm", "7.0.0")
    end
  end

  describe "::package_manager_activate" do
    it "runs the correct corepack prepare command" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("7.0.0/n")
      expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "corepack prepare npm@7.0.0 --activate",
        fingerprint: "corepack prepare <name>@<version> --activate"
      )
      described_class.package_manager_activate("npm", "7.0.0")
    end
  end

  describe "::package_manager_version" do
    it "retrieves the correct package manager version" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("7.0.0-alpha\n")
      expect(described_class.package_manager_version("npm")).to eq("7.0.0-alpha")
    end
  end

  describe "::package_manager_run_command" do
    it "executes the correct command for the package manager" do
      expect(described_class).to receive(:package_manager_run_command).with("npm", "install")

      described_class.package_manager_run_command("npm", "install")
    end
  end

  describe "::package_manager_run_command raise registry error" do
    let(:error_message) do
      "\e[91m➤\e[39m YN0035: │ \e[38;5;166m@sample-group-name/\e[39m\e[38;5;173msample-package-name\e[39m" \
        "\e[38;5;111m@\e[39m\e[38;5;111mnpm:1.0.2\e[39m: The remote server failed to provide the requested resource\n" \
        "\e[91m➤\e[39m YN0035: │   \e[38;5;111mResponse Code\e[39m: \e[38;5;220m404\e[39m (Not Found)\n" \
        "\e[91m➤\e[39m YN0035: │   \e[38;5;111mRequest Method\e[39m: GET\n"
    end

    it "raises RegistryError when the error message includes Response Code 404" do
      error = StandardError.new(error_message)

      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(error)

      expect do
        described_class.package_manager_run_command("yarn", "up -R serve-static --mode=update-lockfile")
      end.to raise_error(Dependabot::RegistryError, "The remote server failed to provide the requested resource")
    end
  end

  describe "::install" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
    end

    context "when corepack succeeds" do
      it "installs, activates, and retrieves the version of the package manager" do
        # Mock for `package_manager_install("npm", "8.0.0")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack install npm@8.0.0 --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only",
          env: {}
        ).and_return("Adding npm@8.0.0 to the cache")

        # Mock for `package_manager_activate("npm", "8.0.0")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@8.0.0 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate"
        ).and_return("")

        # Mock for `local_package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "npm -v",
          fingerprint: "npm -v"
        ).and_return("10.8.2")

        # Mock for `package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack npm -v",
          fingerprint: "corepack npm -v"
        ).and_return("8.0.0")

        # Log expectations
        expect(Dependabot.logger).to receive(:info).with("Installing \"npm@8.0.0\"")
        expect(Dependabot.logger).to receive(:info).with("npm@8.0.0 successfully installed.")
        expect(Dependabot.logger).to receive(:info).with("Activating currently installed version of npm: 8.0.0")
        expect(Dependabot.logger).to receive(:info).with("Fetching version for package manager: npm")
        expect(Dependabot.logger).to receive(:info).with("Installed version of npm: 8.0.0")

        # Test the result
        result = described_class.install("npm", "8.0.0")
        expect(result).to eq("8.0.0")
      end
    end

    context "when corepack fails with unexpected output" do
      it "falls back to the local package manager" do
        # Mock for `package_manager_install("npm", "8.0.0")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack install npm@8.0.0 --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only",
          env: {}
        ).and_return("Unexpected output")

        # Mock for `package_manager_activate("npm", "10.8.2")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@10.8.2 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate"
        ).and_return("")

        # Mock for `local_package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "npm -v",
          fingerprint: "npm -v"
        ).and_return("10.8.2")

        # Mock for `package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack npm -v",
          fingerprint: "corepack npm -v"
        ).and_return("10.8.2")

        # Log expectations
        expect(Dependabot.logger).to receive(:info).with("Installing \"npm@8.0.0\"")
        expect(Dependabot.logger).to receive(:error).with("Corepack installation output unexpected: Unexpected output")
        expect(Dependabot.logger).to receive(:info).with(
          "Falling back to activate the currently installed version of npm."
        )
        expect(Dependabot.logger).to receive(:info).with("Activating currently installed version of npm: 10.8.2")
        expect(Dependabot.logger).to receive(:info).with("Fetching version for package manager: npm")
        expect(Dependabot.logger).to receive(:info).with("Installed version of npm: 10.8.2")

        # Test the result
        result = described_class.install("npm", "8.0.0")
        expect(result).to eq("10.8.2")
      end
    end

    context "when corepack fails with an error" do
      it "falls back to the local package manager" do
        # Mock for `package_manager_install("npm", "8.0.0")` (raises an error)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack install npm@8.0.0 --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only",
          env: {}
        ).and_raise(StandardError, "Corepack failed")

        # Mock for `package_manager_activate("npm", "10.8.2")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@10.8.2 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate"
        ).and_return("")

        # Mock for `local_package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "npm -v",
          fingerprint: "npm -v"
        ).and_return("10.8.2")

        # Mock for `package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack npm -v",
          fingerprint: "corepack npm -v"
        ).and_return("10.8.2")

        # Log expectations
        expect(Dependabot.logger).to receive(:info).with("Installing \"npm@8.0.0\"")
        expect(Dependabot.logger).to receive(:error).with("Error installing npm@8.0.0: Corepack failed")
        expect(Dependabot.logger).to receive(:info).with(
          "Falling back to activate the currently installed version of npm."
        )
        expect(Dependabot.logger).to receive(:info).with("Activating currently installed version of npm: 10.8.2")
        expect(Dependabot.logger).to receive(:info).with("Fetching version for package manager: npm")
        expect(Dependabot.logger).to receive(:info).with("Installed version of npm: 10.8.2")

        # Test the result
        result = described_class.install("npm", "8.0.0")
        expect(result).to eq("10.8.2")
      end
    end

    context "when corepack is not used for bun" do
      it "falls back to the local version of the package manager" do
        # Mock for `local_package_manager_version("bun")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "bun -v",
          fingerprint: "bun -v"
        ).and_return("1.1.39")

        result = described_class.install("bun", "1.1.39")
        expect(result).to eq("1.1.39")
      end
    end
  end

  describe "::npm8?" do
    let(:lockfile_with_v3) do
      Dependabot::DependencyFile.new(name: "package-lock.json", content: { lockfileVersion: 3 }.to_json)
    end
    let(:lockfile_with_v2) do
      Dependabot::DependencyFile.new(name: "package-lock.json", content: { lockfileVersion: 2 }.to_json)
    end
    let(:empty_lockfile) { Dependabot::DependencyFile.new(name: "package-lock.json", content: "") }
    let(:nil_lockfile) { nil }

    context "when the feature flag :enable_corepack_for_npm_and_yarn is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_corepack_for_npm_and_yarn).and_return(true)
        allow(Dependabot::Experiments).to receive(:enabled?).with(:npm_v6_deprecation_warning).and_return(true)
      end

      it "returns true if lockfileVersion is 3 or higher" do
        expect(described_class.npm8?(lockfile_with_v3)).to be true
      end

      it "returns true if lockfileVersion is 2" do
        expect(described_class.npm8?(lockfile_with_v2)).to be true
      end

      it "returns true if lockfile is empty" do
        expect(described_class.npm8?(empty_lockfile)).to be true
      end

      it "returns true if lockfile is nil" do
        expect(described_class.npm8?(nil_lockfile)).to be true
      end
    end

    context "when the feature flag :enable_corepack_for_npm_and_yarn is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_corepack_for_npm_and_yarn).and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:npm_v6_deprecation_warning)
          .and_return(true)
      end

      context "when :npm_fallback_version_above_v6 is enabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:npm_fallback_version_above_v6).and_return(true)
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:npm_v6_deprecation_warning)
            .and_return(true)
        end

        it "returns true if lockfileVersion is 2 or higher" do
          expect(described_class.npm8?(lockfile_with_v2)).to be true
        end

        it "returns true if lockfileVersion is 3 or higher" do
          expect(described_class.npm8?(lockfile_with_v3)).to be true
        end

        it "returns true if lockfile is empty" do
          expect(described_class.npm8?(empty_lockfile)).to be true
        end

        it "returns true if lockfile is nil" do
          expect(described_class.npm8?(nil_lockfile)).to be true
        end
      end

      context "when :npm_fallback_version_above_v6 is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?).with(:npm_fallback_version_above_v6).and_return(false)
        end

        it "returns false for lockfileVersion < 2" do
          lockfile_with_v1 = Dependabot::DependencyFile.new(name: "package-lock.json",
                                                            content: { lockfileVersion: 1 }.to_json)
          expect(described_class.npm8?(lockfile_with_v1)).to be false
        end

        it "returns true for lockfileVersion 2 or higher" do
          expect(described_class.npm8?(lockfile_with_v2)).to be true
        end

        it "returns true for lockfileVersion 3 or higher" do
          expect(described_class.npm8?(lockfile_with_v3)).to be true
        end

        it "returns true if lockfile is empty" do
          expect(described_class.npm8?(empty_lockfile)).to be true
        end

        it "returns false if lockfile is nil" do
          expect(described_class.npm8?(nil_lockfile)).to be true
        end
      end
    end
  end

  describe "::run_node_command" do
    it "executes the correct node command and returns the output" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node --version",
        fingerprint: "node --version"
      ).and_return("v16.13.1")

      expect(described_class.run_node_command("--version", fingerprint: "--version")).to eq("v16.13.1")
    end

    it "executes the node command with a custom fingerprint" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node -e 'console.log(\"Hello World\")'",
        fingerprint: "node custom_fingerprint"
      ).and_return("Hello World")

      expect(
        described_class.run_node_command(
          "-e 'console.log(\"Hello World\")'",
          fingerprint: "custom_fingerprint"
        )
      ).to eq("Hello World")
    end

    it "raises an error if the node command fails" do
      error_context = {
        command: "node invalid_command",
        fingerprint: "node invalid_command"
      }

      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node invalid_command",
        fingerprint: "node invalid_command"
      ).and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Command failed",
          error_context: error_context
        )
      )

      expect { described_class.run_node_command("invalid_command", fingerprint: "invalid_command") }
        .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /Command failed/)
    end
  end

  describe "::node_version" do
    it "returns the correct Node.js version" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node -v",
        fingerprint: "node -v"
      ).and_return("v16.13.1")

      expect(described_class.node_version).to eq("16.13.1")
    end

    it "raises an error if the Node.js version command fails" do
      error_context = {
        command: "node -v",
        fingerprint: "node -v"
      }

      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "node -v",
        fingerprint: "node -v"
      ).and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Error running node command",
          error_context: error_context
        )
      )

      expect(described_class.node_version).to be_nil
    end
  end
end
