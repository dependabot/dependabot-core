# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"

RSpec.describe Dependabot::NpmAndYarn::NativeHelpers do
  describe ".npm_subdependency_update_allowed?" do
    subject(:allowed) do
      described_class.npm_subdependency_update_allowed?(
        lockfile: lockfile,
        updated_content: updated_content,
        dependency: dependency,
        ignored_versions: ignored_versions
      )
    end

    let(:dependency) do
      Dependabot::Dependency.new(name: "child", version: "1.2.0", requirements: [], package_manager: "npm_and_yarn")
    end
    let(:ignored_versions) { [] }
    let(:original_packages) do
      {
        "node_modules/child" => { "version" => "1.0.0" },
        "node_modules/parent/node_modules/child" => { "version" => "2.0.0" }
      }
    end
    let(:updated_packages) { original_packages.merge("node_modules/child" => { "version" => "1.2.0" }) }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "package-lock.json", content: JSON.generate(lockfileVersion: 3, packages: original_packages)
      )
    end
    let(:updated_content) { JSON.generate(lockfileVersion: 3, packages: updated_packages) }

    it "accepts the bound and leaves an unchanged higher occurrence alone" do
      expect(allowed).to be(true)
    end

    context "when a nested occurrence exceeds the bound" do
      let(:updated_packages) do
        super().merge("node_modules/parent/node_modules/child" => { "version" => "2.1.0" })
      end

      it { is_expected.to be(false) }
    end

    context "when npm adds an aliased occurrence above the bound" do
      let(:updated_packages) do
        super().merge("node_modules/@scope/alias" => { "name" => "child", "version" => "2.0.0" })
      end

      it { is_expected.to be(false) }
    end

    context "when an existing alias changes package identity" do
      let(:dependency) do
        Dependabot::Dependency.new(name: "alias", version: "1.2.0", requirements: [], package_manager: "npm_and_yarn")
      end
      let(:original_packages) { { "node_modules/alias" => { "name" => "child", "version" => "1.0.0" } } }
      let(:updated_name) { "unrelated" }
      let(:updated_packages) { { "node_modules/alias" => { "name" => updated_name, "version" => "1.2.0" } } }

      it "rejects a different package even when its version is within the bound" do
        expect(allowed).to be(false)
      end

      context "when the effective package identity is preserved" do
        let(:updated_name) { "child" }

        it { is_expected.to be(true) }

        context "when npm converts a legacy alias to a modern package record" do
          let(:lockfile) do
            Dependabot::DependencyFile.new(
              name: "package-lock.json",
              content: JSON.generate(lockfileVersion: 1, dependencies: { alias: { version: "npm:child@1.0.0" } })
            )
          end

          it { is_expected.to be(true) }
        end
      end
    end

    context "when an ignored range is below the upper bound" do
      let(:ignored_versions) { [">= 1.1.0, < 1.3.0"] }

      it { is_expected.to be(false) }
    end

    context "when only unchanged occurrences match an ignore rule" do
      let(:ignored_versions) { [">= 2"] }

      it { is_expected.to be(true) }
    end

    context "when an updated occurrence has no valid version" do
      let(:updated_packages) { super().merge("node_modules/child" => { "version" => "not-semver" }) }

      it { is_expected.to be(false) }
    end

    context "with a v2 lockfile containing a stale legacy section" do
      let(:updated_content) do
        JSON.generate(
          lockfileVersion: 2,
          packages: updated_packages,
          dependencies: { child: { version: "1.0.0" } }
        )
      end
      let(:updated_packages) { super().merge("node_modules/child" => { "version" => "1.3.0" }) }

      it { is_expected.to be(false) }
    end

    context "with a legacy v1 lockfile" do
      let(:original_dependencies) do
        {
          "child" => { "version" => "1.0.0" },
          "parent" => { "version" => "1.0.0", "dependencies" => { "child" => { "version" => "2.0.0" } } }
        }
      end
      let(:updated_dependencies) { original_dependencies.merge("child" => { "version" => "1.2.0" }) }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "package-lock.json", content: JSON.generate(lockfileVersion: 1, dependencies: original_dependencies)
        )
      end
      let(:updated_content) { JSON.generate(lockfileVersion: 1, dependencies: updated_dependencies) }

      it "accepts a compliant change beside an unchanged higher nested occurrence" do
        expect(allowed).to be(true)
      end

      context "when the top-level installation exceeds the bound" do
        let(:updated_dependencies) { super().merge("child" => { "version" => "1.3.0" }) }

        it { is_expected.to be(false) }
      end

      context "when a nested installation exceeds the bound" do
        let(:updated_dependencies) do
          super().merge(
            "parent" => { "version" => "1.0.0", "dependencies" => { "child" => { "version" => "2.1.0" } } }
          )
        end

        it { is_expected.to be(false) }
      end

      context "when an ignored range is below the bound" do
        let(:ignored_versions) { [">= 1.1.0, < 1.3.0"] }

        it { is_expected.to be(false) }
      end

      context "when only the unchanged nested installation is ignored" do
        let(:ignored_versions) { [">= 2"] }

        it { is_expected.to be(true) }
      end

      context "when only a nested installation changes into an ignored range" do
        let(:ignored_versions) { [">= 1.1.0, < 1.3.0"] }
        let(:updated_dependencies) do
          original_dependencies.merge(
            "parent" => { "version" => "1.0.0", "dependencies" => { "child" => { "version" => "1.2.0" } } }
          )
        end

        it { is_expected.to be(false) }

        context "without the ignored range" do
          let(:ignored_versions) { [] }

          it { is_expected.to be(true) }
        end
      end

      context "when npm converts the lockfile and adds package names" do
        let(:ignored_versions) { [">= 2"] }
        let(:updated_content) do
          JSON.generate(
            lockfileVersion: 2,
            packages: {
              "node_modules/child" => { "name" => "child", "version" => "1.2.0" },
              "node_modules/parent" => { "name" => "parent", "version" => "1.0.0" },
              "node_modules/parent/node_modules/child" => { "name" => "child", "version" => "2.0.0" }
            },
            dependencies: original_dependencies
          )
        end

        it "compares effective versions and names rather than legacy metadata" do
          expect(allowed).to be(true)
        end
      end

      context "when a scoped nested alias is updated" do
        let(:updated_dependencies) do
          super().merge(
            "@scope/parent" => {
              "version" => "1.0.0", "dependencies" => { "@scope/alias" => { "version" => "npm:child@1.3.0" } }
            }
          )
        end

        it { is_expected.to be(false) }

        context "with a compliant alias version" do
          let(:updated_dependencies) do
            super().merge(
              "@scope/parent" => {
                "version" => "1.0.0", "dependencies" => { "@scope/alias" => { "version" => "npm:child@1.2.0" } }
              }
            )
          end

          it { is_expected.to be(true) }
        end

        context "when the aliased package itself is scoped" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@scope/child", version: "1.2.0", requirements: [], package_manager: "npm_and_yarn"
            )
          end
          let(:updated_dependencies) do
            super().merge("@scope/alias" => { "version" => "npm:@scope/child@1.3.0" })
          end

          it { is_expected.to be(false) }
        end
      end
    end

    shared_examples "a removed nested occurrence" do
      it "rejects rebinding to an unchanged higher installation" do
        expect(allowed).to be(false)
      end

      context "with a compliant hoisted installation" do
        let(:hoisted_version) { "1.2.0" }

        it { is_expected.to be(true) }

        context "when the hoisted version is ignored" do
          let(:ignored_versions) { [">= 1.1.0, < 1.3.0"] }

          it { is_expected.to be(false) }
        end
      end

      context "with an invalid hoisted version" do
        let(:hoisted_version) { "not-semver" }

        it { is_expected.to be(false) }
      end

      context "with an empty hoisted version" do
        let(:hoisted_version) { "" }

        it { is_expected.to be(false) }
      end

      context "without a replacement" do
        let(:remove_hoisted) { true }

        it { is_expected.to be(false) }
      end

      context "when the parent no longer requires the dependency" do
        let(:updated_requirements) { {} }

        it { is_expected.to be(true) }
      end

      context "when the parent is also removed" do
        let(:remove_parent) { true }

        it { is_expected.to be(true) }
      end

      context "when deduplication preserves the effective higher version" do
        let(:nested_version) { "2.0.0" }
        let(:ignored_versions) { [">= 2"] }

        it { is_expected.to be(true) }
      end
    end

    context "when a nested occurrence is removed" do
      let(:hoisted_version) { "2.0.0" }
      let(:nested_version) { "1.0.0" }
      let(:parent_name) { "parent" }
      let(:installed_name) { "child" }
      let(:updated_requirements) { { installed_name => ">=1" } }
      let(:remove_parent) { false }
      let(:remove_hoisted) { false }
      let(:original_packages) do
        {
          "node_modules/#{installed_name}" => { "name" => "child", "version" => hoisted_version },
          "node_modules/#{parent_name}" => { "version" => "1.0.0", "dependencies" => { installed_name => ">=1" } },
          "node_modules/#{parent_name}/node_modules/#{installed_name}" =>
            { "name" => "child", "version" => nested_version }
        }
      end
      let(:updated_packages) do
        packages = original_packages.except("node_modules/#{parent_name}/node_modules/#{installed_name}")
        packages["node_modules/#{parent_name}"] = { "version" => "1.0.0", "dependencies" => updated_requirements }
        packages.delete("node_modules/#{parent_name}") if remove_parent
        packages.delete("node_modules/#{installed_name}") if remove_hoisted
        packages
      end

      it_behaves_like "a removed nested occurrence"

      context "with scoped parents and aliases" do
        let(:parent_name) { "@scope/parent" }
        let(:installed_name) { "@scope/alias" }

        it_behaves_like "a removed nested occurrence"
      end

      context "with a nearer compliant installation and an unchanged higher root installation" do
        let(:parent_name) { "@scope/grandparent/node_modules/parent" }
        let(:original_packages) do
          super().merge(
            "node_modules/@scope/grandparent" => { "version" => "1.0.0" },
            "node_modules/@scope/grandparent/node_modules/child" => { "version" => "1.2.0" }
          )
        end

        it { is_expected.to be(true) }
      end

      context "when the parent moves to a different installation path" do
        let(:remove_parent) { true }
        let(:updated_packages) do
          super().merge(
            "node_modules/other-parent" => { "version" => "1.0.0", "dependencies" => updated_requirements }
          )
        end

        it { is_expected.to be(false) }

        context "with a compliant replacement" do
          let(:hoisted_version) { "1.2.0" }

          it { is_expected.to be(true) }
        end
      end

      context "when the replacement has a different package identity" do
        let(:hoisted_version) { "1.2.0" }
        let(:updated_packages) do
          super().merge("node_modules/child" => { "name" => "unrelated", "version" => "1.2.0" })
        end

        it { is_expected.to be(false) }
      end

      context "with no requirement metadata proving the removal is safe" do
        let(:original_packages) do
          super().merge("node_modules/#{parent_name}" => { "version" => "1.0.0" })
        end
        let(:updated_requirements) { {} }

        it { is_expected.to be(false) }
      end

      context "with a legacy v1 lockfile" do
        let(:original_dependencies) do
          {
            "child" => { "version" => hoisted_version },
            "parent" => {
              "version" => "1.0.0", "requires" => { "child" => ">=1" },
              "dependencies" => { "child" => { "version" => nested_version } }
            }
          }
        end
        let(:updated_dependencies) do
          dependencies = original_dependencies.merge(
            "parent" => { "version" => "1.0.0", "requires" => updated_requirements }
          )
          dependencies.delete("parent") if remove_parent
          dependencies.delete("child") if remove_hoisted
          dependencies
        end
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "package-lock.json", content: JSON.generate(lockfileVersion: 1, dependencies: original_dependencies)
          )
        end
        let(:updated_content) { JSON.generate(lockfileVersion: 1, dependencies: updated_dependencies) }

        it_behaves_like "a removed nested occurrence"
      end
    end

    context "when a workspace occurrence is removed" do
      let(:nearer_version) { "2.0.0" }
      let(:original_packages) do
        {
          "node_modules/child" => { "version" => "1.2.0" },
          "packages/node_modules/child" => { "version" => nearer_version },
          "packages/app" => { "version" => "1.0.0", "dependencies" => { "child" => ">=1" } },
          "packages/app/node_modules/child" => { "version" => "1.0.0" }
        }
      end
      let(:updated_packages) { original_packages.except("packages/app/node_modules/child") }

      it "checks nearer ancestor installations before the root" do
        expect(allowed).to be(false)
      end

      context "when the nearer installation is compliant" do
        let(:nearer_version) { "1.2.0" }

        it { is_expected.to be(true) }
      end
    end
  end

  describe ".run_pnpm_audit_fix_command" do
    before do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command) do |command, **|
        command == "-v" ? pnpm_version : ""
      end
    end

    context "with pnpm 11" do
      let(:pnpm_version) { "Corepack warning\n11.25.0\n" }

      it "uses the lockfile update fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix=update", fingerprint: "audit --fix=update")
      end
    end

    context "with pnpm 10" do
      let(:pnpm_version) { "10.16.0" }

      it "uses the compatible override fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix", fingerprint: "audit --fix")
      end
    end
  end
end
