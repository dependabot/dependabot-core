# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::GoModules::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials,
      repo_contents_path: repo_contents_path,
      options: options
    )
  end

  let(:files) { [go_mod, go_sum] }
  let(:project_name) { "go_sum" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:vendor) { false }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:options) { { vendor: vendor } }

  let(:go_mod) do
    Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
  end
  let(:go_mod_body) { fixture("projects", project_name, "go.mod") }

  let(:go_sum) do
    Dependabot::DependencyFile.new(name: "go.sum", content: go_sum_body)
  end
  let(:go_sum_body) { fixture("projects", project_name, "go.sum") }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "go_modules"
    )
  end
  let(:dependency_name) { "rsc.io/quote" }
  let(:dependency_version) { "v1.5.2" }
  let(:dependency_previous_version) { "v1.5.1" }
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: dependency_version,
      groups: [],
      source: {
        type: "default",
        source: "rsc.io/quote"
      }
    }]
  end
  let(:previous_requirements) do
    [{
      file: "go.mod",
      requirement: dependency_previous_version,
      groups: [],
      source: {
        type: "default",
        source: "rsc.io/quote"
      }
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it { expect { updated_files }.to_not output.to_stdout }

    it "includes an updated go.mod" do
      expect(updated_files.find { |f| f.name == "go.mod" }).to_not be_nil
    end

    it "includes an updated go.sum" do
      expect(updated_files.find { |f| f.name == "go.sum" }).to_not be_nil
    end

    context "options" do
      let(:options) { { go_mod_tidy: true } }
      let(:dummy_updater) do
        instance_double(
          Dependabot::GoModules::FileUpdater::GoModUpdater,
          updated_go_mod_content: "",
          updated_go_sum_content: ""
        )
      end

      it "uses the tidy option" do
        expect(Dependabot::GoModules::FileUpdater::GoModUpdater).
          to receive(:new).
          with(
            dependencies: [dependency],
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: "/",
            options: { tidy: true, vendor: false }
          ).and_return(dummy_updater)

        updater.updated_dependency_files
      end
    end

    context "without a go.sum" do
      let(:project_name) { "simple" }
      let(:files) { [go_mod] }

      it "doesn't include a go.sum" do
        expect(updated_files.find { |f| f.name == "go.sum" }).to be_nil
      end
    end

    context "without repo_contents_path" do
      let(:updater) do
        described_class.new(
          dependency_files: files,
          dependencies: [dependency],
          credentials: [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        )
      end

      it "includes an updated go.mod" do
        expect(updated_files.find { |f| f.name == "go.mod" }).to_not be_nil
      end

      it "includes an updated go.sum" do
        expect(updated_files.find { |f| f.name == "go.sum" }).to_not be_nil
      end
    end

    context "vendoring" do
      let(:project_name) { "vendor" }
      let(:vendor) { true }

      let(:dependency_name) { "github.com/pkg/errors" }
      let(:dependency_version) { "v0.9.1" }
      let(:dependency_previous_version) { "v0.8.0" }
      let(:requirements) do
        [{
          file: "go.mod",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "default",
            source: "github.com/pkg"
          }
        }]
      end
      let(:previous_requirements) do
        [{
          file: "go.mod",
          requirement: dependency_previous_version,
          groups: [],
          source: {
            type: "default",
            source: "github.com/pkg"
          }
        }]
      end

      it "updates the version" do
        expect(go_mod_body).to include("github.com/pkg/errors v0.8.0")

        updater.updated_dependency_files

        go_mod_file = updater.updated_dependency_files.find do |file|
          file.name == "go.mod"
        end

        expect(go_mod_file.content).to include "github.com/pkg/errors v0.9.1"
      end

      it "includes the vendored files" do
        expect(updater.updated_dependency_files.map(&:name)).to match_array(
          %w(
            go.mod
            go.sum
            vendor/github.com/pkg/errors/.travis.yml
            vendor/github.com/pkg/errors/Makefile
            vendor/github.com/pkg/errors/README.md
            vendor/github.com/pkg/errors/errors.go
            vendor/github.com/pkg/errors/go113.go
            vendor/github.com/pkg/errors/stack.go
            vendor/modules.txt
          )
        )
      end

      it "updates the vendor/modules.txt file to the right version" do
        modules_file = updater.updated_dependency_files.find do |file|
          file.name == "vendor/modules.txt"
        end

        expect(modules_file.content).to include "github.com/pkg/errors v0.9.1"
      end

      it "includes the new source code" do
        # Sample to verify the source code matches:
        # https://github.com/pkg/errors/compare/v0.8.0...v0.9.1
        stack_file = updater.updated_dependency_files.find do |file|
          file.name == "vendor/github.com/pkg/errors/stack.go"
        end

        expect(stack_file.content).to include(
          <<~LINE
            Format formats the stack of Frames according to the fmt.Formatter interface.
          LINE
        )
        expect(stack_file.content).to_not include(
          <<~LINE
            segments from the beginning of the file path until the number of path
          LINE
        )
      end
    end
  end
end
