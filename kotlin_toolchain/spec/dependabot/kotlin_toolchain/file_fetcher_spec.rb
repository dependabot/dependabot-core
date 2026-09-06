# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/errors"
require "dependabot/kotlin_toolchain/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::KotlinToolchain::FileFetcher do
  let(:project) { "nested_templates" }
  let(:repo_contents_path) { build_tmp_repo(project) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/kotlin-toolchain",
      directory: "/"
    )
  end
  let(:fetcher) do
    described_class.new(
      source: source,
      credentials: [],
      repo_contents_path: repo_contents_path
    )
  end

  before { allow(fetcher).to receive(:allow_beta_ecosystems?).and_return(true) }

  it_behaves_like "a dependency file fetcher"

  context "when beta ecosystems are not enabled" do
    before { allow(fetcher).to receive(:allow_beta_ecosystems?).and_return(false) }

    it "refuses to fetch anything" do
      expect { fetcher.files }.to raise_error(
        Dependabot::DependencyFileNotFound,
        /Kotlin Toolchain support is currently in beta/
      )
    end
  end

  describe ".required_files_in?" do
    it "requires a wrapper and a Kotlin Toolchain manifest" do
      expect(described_class.required_files_in?(%w(kotlin project.yaml))).to be(true)
      expect(described_class.required_files_in?(%w(kotlin.bat module.yaml))).to be(true)
      expect(described_class.required_files_in?(["kotlin", "libs.versions.toml"])).to be(false)
      expect(described_class.required_files_in?(%w(kotlin common.module-template.yaml))).to be(false)
      expect(described_class.required_files_in?(["project.yaml"])).to be(false)
    end
  end

  describe "#files" do
    it "fetches globbed modules, recursively applied templates, and the catalog" do
      expect(fetcher.files.map(&:name)).to contain_exactly(
        "kotlin",
        "kotlin.bat",
        "project.yaml",
        "module.yaml",
        "plugins/example/module.yaml",
        "base.module-template.yaml",
        "nested.module-template.yaml",
        "libs.versions.toml"
      )
    end

    it "reports the wrapper as the package-manager version" do
      expect(fetcher.ecosystem_versions).to eq(
        package_managers: { "kotlin-toolchain" => "0.12.0-dev-4188" }
      )
    end

    context "with excluded paths" do
      before { fetcher.exclude_paths = ["plugins/**", "libs.versions.toml"] }

      it "skips the excluded module, its templates and the catalog" do
        expect(fetcher.files.map(&:name)).to contain_exactly(
          "kotlin",
          "kotlin.bat",
          "project.yaml",
          "module.yaml"
        )
      end
    end

    context "with the root module excluded" do
      before { fetcher.exclude_paths = ["module.yaml"] }

      it "leaves it out like any other excluded file" do
        expect(fetcher.files.map(&:name)).to contain_exactly(
          "kotlin",
          "kotlin.bat",
          "project.yaml",
          "plugins/example/module.yaml",
          "base.module-template.yaml",
          "nested.module-template.yaml",
          "libs.versions.toml"
        )
      end
    end

    context "with a single module and no project file" do
      let(:project) { "module_only" }

      it "fetches the Unix wrapper, the module, its template and the Gradle catalog" do
        expect(fetcher.files.map(&:name)).to contain_exactly(
          "kotlin",
          "module.yaml",
          "base.module-template.yaml",
          "gradle/libs.versions.toml"
        )
      end

      it "reports the 0.11 wrapper version" do
        expect(fetcher.ecosystem_versions).to eq(
          package_managers: { "kotlin-toolchain" => "0.11.1" }
        )
      end
    end

    context "with unusual module and template references" do
      let(:project) { "odd_manifests" }

      it "keeps the references it can resolve and drops the rest" do
        expect(fetcher.files.map(&:name)).to contain_exactly(
          "kotlin",
          "project.yaml",
          "module.yaml",
          "libs/one/module.yaml",
          "shared.module-template.yaml"
        )
      end
    end

    context "without a wrapper" do
      let(:project) { "missing_wrapper" }

      it "raises" do
        expect { fetcher.files }
          .to raise_error(Dependabot::DependencyFileNotFound, /Kotlin Toolchain wrapper is missing/)
      end
    end

    context "without a project or module manifest" do
      let(:project) { "catalog_only" }

      it "raises and explains what the repository must contain" do
        expect { fetcher.files }.to raise_error(
          Dependabot::DependencyFileNotFound,
          /Repo must contain a Kotlin Toolchain wrapper and a project\.yaml or module\.yaml file/
        )
      end
    end
  end
end
