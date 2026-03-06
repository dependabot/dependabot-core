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

        expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq(
          [
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
          ]
        )
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

        expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq(
          [
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
          ]
        )
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
        fingerprint: "corepack prepare <name>@<version> --activate",
        env: {}
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
        # Mock for `package_manager_activate("npm", "8.0.0")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@8.0.0 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate",
          env: {}
        ).and_return("Preparing npm@8.0.0 for immediate activation...")

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
        # Mock for `package_manager_activate("npm", "8.0.0")` (raises an error)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@8.0.0 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate",
          env: {}
        ).and_raise(StandardError, "Unexpected error")

        # Mock for `local_package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "npm -v",
          fingerprint: "npm -v"
        ).and_return("10.8.2")

        # Mock for `package_manager_activate("npm", "10.8.2")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@10.8.2 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate",
          env: {}
        ).and_return("")

        # Mock for `package_manager_version("npm")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack npm -v",
          fingerprint: "corepack npm -v"
        ).and_return("10.8.2")

        # Log expectations
        expect(Dependabot.logger).to receive(:info).with("Installing \"npm@8.0.0\"")
        expect(Dependabot.logger).to receive(:error).with(
          "Error activating npm@8.0.0: Unexpected error"
        )
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
        # Mock for `package_manager_activate("npm", "8.0.0")` (raises an error)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@8.0.0 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate",
          env: {}
        ).and_raise(StandardError, "Corepack failed")

        # Mock for `package_manager_activate("npm", "10.8.2")`
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "corepack prepare npm@10.8.2 --activate",
          fingerprint: "corepack prepare <name>@<version> --activate",
          env: {}
        ).and_return("Preparing npm@10.8.2 for immediate activation...")

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
        expect(Dependabot.logger).to receive(:error).with("Error activating npm@8.0.0: Corepack failed")
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
  end

  describe "::parse_npm8?" do
    let(:lockfile_with_v3) do
      Dependabot::DependencyFile.new(name: "package-lock.json", content: { lockfileVersion: 3 }.to_json)
    end
    let(:lockfile_with_v2) do
      Dependabot::DependencyFile.new(name: "package-lock.json", content: { lockfileVersion: 2 }.to_json)
    end
    let(:lockfile_with_v1) do
      Dependabot::DependencyFile.new(name: "package-lock.json", content: { lockfileVersion: 1 }.to_json)
    end
    let(:empty_lockfile) { Dependabot::DependencyFile.new(name: "package-lock.json", content: "") }
    let(:nil_lockfile) { nil }

    context "when the feature flag :enable_corepack_for_npm_and_yarn is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_corepack_for_npm_and_yarn).and_return(true)
      end

      it "returns true if lockfileVersion is 3 or higher" do
        expect(described_class.parse_npm8?(lockfile_with_v3)).to be true
      end

      it "returns true if lockfileVersion is 2" do
        expect(described_class.parse_npm8?(lockfile_with_v2)).to be true
      end

      it "returns true if lockfileVersion is 1" do
        expect(described_class.parse_npm8?(lockfile_with_v1)).to be false
      end

      it "returns true if lockfile is empty" do
        expect(described_class.parse_npm8?(empty_lockfile)).to be true
      end

      it "returns true if lockfile is nil" do
        expect(described_class.parse_npm8?(nil_lockfile)).to be true
      end
    end

    context "when the feature flag :enable_corepack_for_npm_and_yarn is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_corepack_for_npm_and_yarn).and_return(false)
      end

      it "returns true if 3=< lockfileVersion" do
        expect(described_class.parse_npm8?(lockfile_with_v3)).to be true
      end

      it "returns true if 2=< lockfileVersion <3" do
        expect(described_class.parse_npm8?(lockfile_with_v2)).to be true
      end

      it "returns false if 1=< lockfileVersion <2" do
        expect(described_class.parse_npm8?(lockfile_with_v1)).to be false
      end

      it "returns true if lockfile is empty" do
        expect(described_class.parse_npm8?(empty_lockfile)).to be true
      end

      it "returns true if lockfile is nil" do
        expect(described_class.parse_npm8?(nil_lockfile)).to be true
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

  describe "credential handling for corepack" do
    let(:credentials) do
      [
        Dependabot::Credential.new(
          "type" => "npm_registry",
          "registry" => "jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual",
          "token" => "test-token-123",
          "replaces-base" => true
        )
      ]
    end

    let(:npmrc_file) do
      Dependabot::DependencyFile.new(
        name: ".npmrc",
        content: "registry=https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual\n"
      )
    end

    let(:dependency_files) { [npmrc_file] }

    before do
      described_class.dependency_files = dependency_files
      described_class.credentials = credentials
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_private_registry_for_corepack).and_return(true)
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_corepack_for_npm_and_yarn).and_return(true)
    end

    after do
      described_class.dependency_files = []
      described_class.credentials = []
    end

    describe ".build_corepack_env_variables" do
      it "builds environment variables from credentials with only registry" do
        env = described_class.send(:build_corepack_env_variables)

        expect(env).not_to be_nil
        expect(env["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        expect(env["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        expect(env["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        expect(env["COREPACK_NPM_TOKEN"]).to eq("test-token-123")
      end

      context "when experiment flag is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_private_registry_for_corepack).and_return(false)
        end

        it "returns nil" do
          env = described_class.send(:build_corepack_env_variables)
          expect(env).to be_nil
        end
      end

      context "when dependency_files is empty" do
        before { described_class.dependency_files = [] }

        it "still builds env from credentials if present" do
          env = described_class.send(:build_corepack_env_variables)
          # Registry helper can still find registry from credentials even without files
          expect(env).not_to be_nil
          expect(env["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        end
      end

      context "when credentials is empty" do
        before { described_class.credentials = [] }

        it "still finds registry from .npmrc file" do
          env = described_class.send(:build_corepack_env_variables)
          # Can still extract registry from .npmrc even without credentials
          expect(env).not_to be_nil
          expect(env["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        end
      end

      context "with non-replaces-base credential" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "npm-token"
            )
          ]
        end

        it "returns env with registry from .npmrc" do
          env = described_class.send(:build_corepack_env_variables)

          # Returns env based on .npmrc content since credential doesn't replace base
          expect(env).not_to be_nil
          expect(env["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(env["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
        end
      end

      context "with replaces-base credential" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              "type" => "npm_registry",
              "registry" => "custom.registry.com",
              "token" => "custom-token",
              "replaces-base" => true
            )
          ]
        end

        it "builds env variables for replaces-base registry without token" do
          env = described_class.send(:build_corepack_env_variables)

          expect(env).not_to be_nil
          expect(env["COREPACK_NPM_REGISTRY"]).to eq("https://custom.registry.com")
          expect(env["npm_config_registry"]).to eq("https://custom.registry.com")
          expect(env["registry"]).to eq("https://custom.registry.com")
          expect(env["COREPACK_NPM_TOKEN"]).to eq("custom-token")
        end
      end
    end

    describe ".merge_corepack_env" do
      it "merges corepack env with provided env" do
        original_env = { "PATH" => "/usr/bin", "NODE_ENV" => "test" }

        # Stub build_corepack_env_variables to return known values
        allow(described_class).to receive(:build_corepack_env_variables).and_return(
          {
            "COREPACK_NPM_REGISTRY" => "https://test.registry.com",
            "npm_config_registry" => "https://test.registry.com",
            "registry" => "https://test.registry.com",
            "COREPACK_NPM_TOKEN" => "test-token"
          }
        )

        merged = described_class.send(:merge_corepack_env, original_env)

        expect(merged["PATH"]).to eq("/usr/bin")
        expect(merged["NODE_ENV"]).to eq("test")
        expect(merged["COREPACK_NPM_REGISTRY"]).to eq("https://test.registry.com")
        expect(merged["npm_config_registry"]).to eq("https://test.registry.com")
        expect(merged["registry"]).to eq("https://test.registry.com")
        expect(merged["COREPACK_NPM_TOKEN"]).to eq("test-token")
      end

      it "returns original env when corepack env is nil" do
        original_env = { "PATH" => "/usr/bin" }

        allow(described_class).to receive(:build_corepack_env_variables).and_return(nil)

        merged = described_class.send(:merge_corepack_env, original_env)

        expect(merged).to eq(original_env)
      end

      it "returns original env when corepack env is empty" do
        original_env = { "PATH" => "/usr/bin" }

        allow(described_class).to receive(:build_corepack_env_variables).and_return({})

        merged = described_class.send(:merge_corepack_env, original_env)

        expect(merged).to eq(original_env)
      end

      it "returns corepack env when original env is nil" do
        corepack_env = {
          "COREPACK_NPM_REGISTRY" => "https://test.registry.com",
          "npm_config_registry" => "https://test.registry.com",
          "registry" => "https://test.registry.com",
          "COREPACK_NPM_TOKEN" => "test-token"
        }

        allow(described_class).to receive(:build_corepack_env_variables).and_return(corepack_env)

        merged = described_class.send(:merge_corepack_env, nil)

        expect(merged).to eq(corepack_env)
      end

      it "prefers provided env over corepack env for duplicate keys" do
        original_env = { "COREPACK_NPM_TOKEN" => "override-token" }

        allow(described_class).to receive(:build_corepack_env_variables).and_return(
          { "COREPACK_NPM_TOKEN" => "default-token" }
        )

        merged = described_class.send(:merge_corepack_env, original_env)

        expect(merged["COREPACK_NPM_TOKEN"]).to eq("override-token")
      end
    end

    describe ".run_npm_command integration" do
      it "automatically injects corepack env variables with only registry" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_cmd, options|
          expect(options[:env]).not_to be_nil
          expect(options[:env]["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(options[:env]["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(options[:env]["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(options[:env]["COREPACK_NPM_TOKEN"]).to eq("test-token-123")
          ""
        end

        described_class.run_npm_command("install")
      end

      it "preserves manually provided env variables" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_cmd, options|
          expect(options[:env]["CUSTOM_VAR"]).to eq("custom-value")
          expect(options[:env]["COREPACK_NPM_REGISTRY"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(options[:env]["npm_config_registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          expect(options[:env]["registry"]).to eq("https://jfrogghdemo.jfrog.io/artifactory/api/npm/npm-virtual")
          ""
        end

        described_class.run_npm_command("install", env: { "CUSTOM_VAR" => "custom-value" })
      end
    end

    describe "thread-local storage" do
      it "isolates dependency_files across threads" do
        thread1_files = [npmrc_file]
        thread2_files = [Dependabot::DependencyFile.new(name: "other.npmrc", content: "")]

        results = {}

        threads = [
          Thread.new do
            described_class.dependency_files = thread1_files
            sleep 0.01
            results[:thread1] = described_class.dependency_files
          end,
          Thread.new do
            described_class.dependency_files = thread2_files
            sleep 0.01
            results[:thread2] = described_class.dependency_files
          end
        ]

        threads.each(&:join)

        expect(results[:thread1]).to eq(thread1_files)
        expect(results[:thread2]).to eq(thread2_files)
      end

      it "isolates credentials across threads" do
        thread1_creds = credentials
        thread2_creds = [Dependabot::Credential.new("type" => "git_source")]

        results = {}

        threads = [
          Thread.new do
            described_class.credentials = thread1_creds
            sleep 0.01
            results[:thread1] = described_class.credentials
          end,
          Thread.new do
            described_class.credentials = thread2_creds
            sleep 0.01
            results[:thread2] = described_class.credentials
          end
        ]

        threads.each(&:join)

        expect(results[:thread1]).to eq(thread1_creds)
        expect(results[:thread2]).to eq(thread2_creds)
      end
    end
  end
end
