# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/helm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Helm::FileUpdater do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "redis",
      version: "20.11.3",
      previous_version: "17.11.3",
      requirements: [{
        requirement: "20.11.3",
        groups: [],
        metadata: { type: :helm_chart },
        file: "Chart.yaml",
        source: { registry: "https://charts.bitnami.com/bitnami", tag: "20.11.3" }
      }],
      previous_requirements: [{
        requirement: "17.11.3",
        groups: [],
        metadata: { type: :helm_chart },
        file: "Chart.yaml",
        source: { registry: "https://charts.bitnami.com/bitnami", tag: "17.11.3" }
      }],
      package_manager: "helm"
    )
  end
  sig { returns(String) }
  let(:helmfile_body) do
    fixture("helm", "v3", "single.yaml")
  end
  sig { returns(Dependabot::DependencyFile) }
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      content: helmfile_body,
      name: "Chart.yaml"
    )
  end
  sig { returns(T::Array[Dependabot::Credential]) }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:files) { [dockerfile] }
  sig { returns(Dependabot::Helm::FileUpdater) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#updated_dependency_files" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      expect(updated_files).to all(be_a(Dependabot::DependencyFile))
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated Chart.yaml" do
      sig { returns(Dependabot::DependencyFile) }
      subject(:updated_helmfile) do
        T.must(updated_files.find { |f| f.name == "Chart.yaml" })
      end

      sig { returns(T::Hash[String, Object]) }
      let(:yaml_content) do
        YAML.safe_load T.must(updated_helmfile.content)
      end

      its(:content) { is_expected.to include "- name: redis\n    version: 20.11.3" }

      it "contains the expected YAML content" do
        expect(yaml_content).to eq(
          {
            "apiVersion" => "v2",
            "name" => "example-service",
            "version" => "0.1.0",
            "dependencies" => [{
              "name" => "redis",
              "version" => "20.11.3",
              "repository" => "https://charts.bitnami.com/bitnami"
            }]
          }
        )
      end
    end

    context "when multiple identical lines need to be updated" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:helmfile_body) do
        fixture("helm", "v3", "basic.yaml")
      end
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "mongodb",
          version: "19.10.2",
          previous_version: "13.9.1",
          requirements: [{
            requirement: "19.10.2",
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: { registry: "https://charts.bitnami.com/bitnami", tag: "19.10.2" }
          }],
          previous_requirements: [{
            requirement: "13.9.1",
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: { registry: "https://charts.bitnami.com/bitnami", tag: "13.9.1" }
          }],
          package_manager: "helm"
        )
      end
      # rubocop:enable RSpec/ScatteredLet

      describe "the updated Chart.yaml" do
        sig { returns(Dependabot::DependencyFile) }
        subject(:updated_helmfile) do
          T.must(updated_files.find { |f| f.name == "Chart.yaml" })
        end

        its(:content) { is_expected.to include "- name: redis\n    version: 17.11.3" }
        its(:content) { is_expected.to include "- name: mongodb\n    version: 19.10.2" }
      end
    end

    context "when the dependency is from a private registry" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:helmfile_body) do
        fixture("helm", "v3", "private_reg.yaml")
      end
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "myreg/redis",
          version: "20.11.3",
          previous_version: "17.11.3",
          requirements: [{
            requirement: nil,
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: {
              registry: "registry-host.io:5000",
              tag: "20.11.3"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.11.3"
            }
          }],
          package_manager: "helm"
        )
      end
      # rubocop:enable RSpec/ScatteredLet

      its(:length) { is_expected.to eq(1) }

      describe "the updated Chart.yaml" do
        sig { returns(Dependabot::DependencyFile) }
        subject(:updated_helmfile) do
          T.must(updated_files.find { |f| f.name == "Chart.yaml" })
        end

        its(:content) { is_expected.to include "- name: myreg/redis\n    version: 20.11.3" }
      end
    end

    context "when the same chart is in two files and only one changes" do
      # Regression: the unchanged file must be skipped, not written back
      # identically (which would raise "Expected content to change!").
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Chart.yaml",
            content: "name: a\ndependencies:\n  - name: common\n    version: 1.0.0\n"
          ),
          Dependabot::DependencyFile.new(
            name: "sub/Chart.yaml",
            content: "name: b\ndependencies:\n  - name: common\n    version: \">1.0.0\"\n"
          )
        ]
      end
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "common",
          version: "1.0.0",
          previous_version: "1.0.0",
          requirements: [
            { file: "Chart.yaml", requirement: "2.0.0", groups: [],
              source: { tag: "1.0.0" }, metadata: { type: :helm_chart } },
            { file: "sub/Chart.yaml", requirement: ">1.0.0", groups: [],
              source: { tag: ">1.0.0" }, metadata: { type: :helm_chart } }
          ],
          previous_requirements: [
            { file: "Chart.yaml", requirement: nil, groups: [],
              source: { tag: "1.0.0" }, metadata: { type: :helm_chart } },
            { file: "sub/Chart.yaml", requirement: nil, groups: [],
              source: { tag: ">1.0.0" }, metadata: { type: :helm_chart } }
          ],
          package_manager: "helm"
        )
      end
      # rubocop:enable RSpec/ScatteredLet

      it "updates only the changed file" do
        expect(updated_files.map(&:name)).to eq(["Chart.yaml"])
        expect(updated_files.fetch(0).content).to include("version: 2.0.0")
      end
    end
  end
end
