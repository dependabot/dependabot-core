# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/go_modules/file_updater/updater_helper"

RSpec.describe Dependabot::GoModules::FileUpdater::UpdaterHelper do
  describe ".configure_git_vanity_imports" do
    let(:dependencies) { [] }

    before do
      allow(Dependabot::SharedHelpers).to receive(:configure_git_to_use_https)
      allow(Dependabot.logger).to receive(:info)
      allow(Dependabot.logger).to receive(:warn)
    end

    context "with no dependencies" do
      let(:dependencies) { [] }

      it "returns early without configuration" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(Dependabot::SharedHelpers).not_to have_received(:configure_git_to_use_https)
        expect(Dependabot.logger).not_to have_received(:info)
      end
    end

    context "with only public hosting provider dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/user/repo",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      it "returns early without configuration" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(Dependabot::SharedHelpers).not_to have_received(:configure_git_to_use_https)
        expect(Dependabot.logger).not_to have_received(:info)
      end
    end

    context "with vanity import dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        # Mock successful vanity import resolution
        resolver = instance_double(Dependabot::GoModules::VanityImportResolver)
        allow(Dependabot::GoModules::VanityImportResolver).to receive(:new)
          .with(dependencies: dependencies)
          .and_return(resolver)
        allow(resolver).to receive(:has_vanity_imports?).and_return(true)
        allow(resolver).to receive(:resolve_git_hosts).and_return(["git.example.com"])
      end

      it "configures git rewrite rules for discovered git hosts" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(Dependabot::SharedHelpers).to have_received(:configure_git_to_use_https)
          .with("git.example.com")
        expect(Dependabot.logger).to have_received(:info)
          .with("Configured git rewrite rules for 1 vanity import host(s)")
      end
    end

    context "with multiple vanity import dependencies resolving to multiple hosts" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg1",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          ),
          Dependabot::Dependency.new(
            name: "custom.company.com/pkg2",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        resolver = instance_double(Dependabot::GoModules::VanityImportResolver)
        allow(Dependabot::GoModules::VanityImportResolver).to receive(:new)
          .with(dependencies: dependencies)
          .and_return(resolver)
        allow(resolver).to receive(:has_vanity_imports?).and_return(true)
        allow(resolver).to receive(:resolve_git_hosts)
          .and_return(["git.example.com", "git.company.com"])
      end

      it "configures git rewrite rules for all discovered hosts" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(Dependabot::SharedHelpers).to have_received(:configure_git_to_use_https)
          .with("git.example.com")
        expect(Dependabot::SharedHelpers).to have_received(:configure_git_to_use_https)
          .with("git.company.com")
        expect(Dependabot.logger).to have_received(:info)
          .with("Configured git rewrite rules for 2 vanity import host(s)")
      end
    end

    context "when vanity import resolution fails" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        resolver = instance_double(Dependabot::GoModules::VanityImportResolver)
        allow(Dependabot::GoModules::VanityImportResolver).to receive(:new)
          .with(dependencies: dependencies)
          .and_return(resolver)
        allow(resolver).to receive(:has_vanity_imports?).and_return(true)
        allow(resolver).to receive(:resolve_git_hosts)
          .and_raise(StandardError.new("Network timeout"))
      end

      it "logs a warning but does not fail the entire process" do
        expect { described_class.configure_git_vanity_imports(dependencies) }
          .not_to raise_error

        expect(Dependabot.logger).to have_received(:warn)
          .with("Failed to configure vanity git hosts: Network timeout")
        expect(Dependabot::SharedHelpers).not_to have_received(:configure_git_to_use_https)
      end
    end

    context "when resolver indicates no vanity imports" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        resolver = instance_double(Dependabot::GoModules::VanityImportResolver)
        allow(Dependabot::GoModules::VanityImportResolver).to receive(:new)
          .with(dependencies: dependencies)
          .and_return(resolver)
        allow(resolver).to receive(:has_vanity_imports?).and_return(false)
      end

      it "returns early without calling resolve_git_hosts" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(resolver).not_to have_received(:resolve_git_hosts)
        expect(Dependabot::SharedHelpers).not_to have_received(:configure_git_to_use_https)
      end
    end

    context "when resolver returns empty git hosts array" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "go.example.com/pkg",
            version: "v1.0.0",
            requirements: [],
            package_manager: "go_modules"
          )
        ]
      end

      before do
        resolver = instance_double(Dependabot::GoModules::VanityImportResolver)
        allow(Dependabot::GoModules::VanityImportResolver).to receive(:new)
          .with(dependencies: dependencies)
          .and_return(resolver)
        allow(resolver).to receive(:has_vanity_imports?).and_return(true)
        allow(resolver).to receive(:resolve_git_hosts).and_return([])
      end

      it "does not configure any git hosts" do
        described_class.configure_git_vanity_imports(dependencies)

        expect(Dependabot::SharedHelpers).not_to have_received(:configure_git_to_use_https)
        expect(Dependabot.logger).not_to have_received(:info)
      end
    end
  end
end
