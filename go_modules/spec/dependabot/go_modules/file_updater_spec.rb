# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater"
require "dependabot/shared_helpers"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::GoModules::FileUpdater do
  let(:previous_git_author_name) { ENV.fetch("GIT_AUTHOR_NAME", nil) }
  let(:previous_git_author_email) { ENV.fetch("GIT_AUTHOR_EMAIL", nil) }
  let(:previous_git_committer_name) { ENV.fetch("GIT_COMMITTER_NAME", nil) }
  let(:previous_git_committer_email) { ENV.fetch("GIT_COMMITTER_EMAIL", nil) }
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
  let(:dependency_previous_version) { "v1.5.1" }
  let(:dependency_version) { "v1.5.2" }
  let(:dependency_name) { "rsc.io/quote" }
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
  let(:go_sum_body) { fixture("projects", project_name, "go.sum") }
  let(:go_sum) do
    Dependabot::DependencyFile.new(name: "go.sum", content: go_sum_body)
  end
  let(:go_mod_body) { fixture("projects", project_name, "go.mod") }
  let(:go_mod) do
    Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
  end
  let(:credentials) { [] }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:project_name) { "go_sum" }
  let(:files) { [go_mod, go_sum] }
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it { expect { updated_files }.not_to output.to_stdout }

    it "includes an updated go.mod" do
      expect(updated_files.find { |f| f.name == "go.mod" }).not_to be_nil
    end

    it "includes an updated go.sum" do
      expect(updated_files.find { |f| f.name == "go.sum" }).not_to be_nil
    end

    context "with an indirect dependency update" do
      let(:requirements) { [] }
      let(:previous_requirements) { [] }

      it "includes an updated go.mod" do
        expect(updated_files.find { |f| f.name == "go.mod" }).not_to be_nil
      end

      it "includes an updated go.sum" do
        ENV["GIT_AUTHOR_NAME"] = previous_git_author_name
        ENV["GIT_AUTHOR_EMAIL"] = previous_git_author_email
        ENV["GIT_COMMITTER_NAME"] = previous_git_committer_name
        ENV["GIT_COMMITTER_EMAIL"] = previous_git_committer_email
        expect(updated_files.find { |f| f.name == "go.sum" }).not_to be_nil
      end
    end

    context "with an invalid module path" do
      let(:stderr) do
        <<~STDERR
          go get: github.com/etcd-io/bbolt@none updating to
          	github.com/etcd-io/bbolt@v1.3.5: parsing go.mod:
          	module declares its path as: go.etcd.io/bbolt
          	        but was required as: github.com/etcd-io/bbolt
        STDERR
      end

      before do
        # We don't have git configured in prod, so simulate the same setup here

        ENV["GIT_AUTHOR_NAME"] = nil
        ENV["GIT_AUTHOR_EMAIL"] = nil
        ENV["GIT_COMMITTER_NAME"] = nil
        ENV["GIT_COMMITTER_EMAIL"] = nil
        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "go get").and_return(["", stderr, exit_status])
      end

      after do
        ENV["GIT_AUTHOR_NAME"] = previous_git_author_name
        ENV["GIT_AUTHOR_EMAIL"] = previous_git_author_email
        ENV["GIT_COMMITTER_NAME"] = previous_git_committer_name
        ENV["GIT_COMMITTER_EMAIL"] = previous_git_committer_email
      end

      it "raises a helpful error" do
        expect { updated_files }.to raise_error(Dependabot::GoModulePathMismatch)
      end
    end

    context "without a go.sum" do
      let(:project_name) { "simple" }
      let(:files) { [go_mod] }

      it "doesn't include a go.sum" do
        ENV["GIT_AUTHOR_NAME"] = previous_git_author_name
        ENV["GIT_AUTHOR_EMAIL"] = previous_git_author_email
        ENV["GIT_COMMITTER_NAME"] = previous_git_committer_name
        ENV["GIT_COMMITTER_EMAIL"] = previous_git_committer_email
        expect(updated_files.find { |f| f.name == "go.sum" }).to be_nil
      end
    end

    context "when go.mod specifies a pre-1.21 version but uses a 1.21 dependency" do
      let(:project_name) { "toolchain" }
      let(:files) { [go_mod] }

      it "doesn't add a toolchain directive" do
        expect(updated_files.first.content).not_to include("toolchain")
      end
    end

    context "without a clone of the repository" do
      let(:updater) do
        described_class.new(
          dependency_files: files,
          dependencies: [dependency],
          credentials: [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }],
          repo_contents_path: nil
        )
      end

      before do
        # We don't have git configured in prod, so simulate the same setup here

        ENV["GIT_AUTHOR_NAME"] = nil
        ENV["GIT_AUTHOR_EMAIL"] = nil
        ENV["GIT_COMMITTER_NAME"] = nil
        ENV["GIT_COMMITTER_EMAIL"] = nil
      end

      after do
        ENV["GIT_AUTHOR_NAME"] = previous_git_author_name
        ENV["GIT_AUTHOR_EMAIL"] = previous_git_author_email
        ENV["GIT_COMMITTER_NAME"] = previous_git_committer_name
        ENV["GIT_COMMITTER_EMAIL"] = previous_git_committer_email
      end

      it "includes an updated go.mod" do
        expect(updated_files.find { |f| f.name == "go.mod" }).not_to be_nil
      end

      it "includes an updated go.sum" do
        expect(updated_files.find { |f| f.name == "go.sum" }).not_to be_nil
      end

      it "disables the tidy option" do
        double = instance_double(
          Dependabot::GoModules::FileUpdater::GoModUpdater,
          updated_go_mod_content: "",
          updated_go_sum_content: ""
        )

        expect(Dependabot::GoModules::FileUpdater::GoModUpdater)
          .to receive(:new)
          .with(
            dependencies: anything,
            dependency_files: anything,
            credentials: anything,
            repo_contents_path: anything,
            directory: anything,
            options: { tidy: false, vendor: false, goprivate: "*" }
          ).and_return(double)

        updater.updated_dependency_files
      end

      context "when dependency files are nested in a directory" do
        let(:go_mod) do
          Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body,
                                         directory: "/nested")
        end
        let(:go_sum) do
          Dependabot::DependencyFile.new(name: "go.sum", content: go_sum_body,
                                         directory: "/nested")
        end

        it "includes an updated go.mod" do
          expect(updated_files.find { |f| f.name == "go.mod" }).not_to be_nil
        end

        it "includes an updated go.sum" do
          expect(updated_files.find { |f| f.name == "go.sum" }).not_to be_nil
        end
      end
    end

    context "when dealing with vendoring" do
      let(:project_name) { "vendor" }
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

      it "updates the go.mod" do
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

        expect(modules_file.content)
          .not_to include "github.com/pkg/errors v0.8.0"
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
        expect(stack_file.content).not_to include(
          <<~LINE
            segments from the beginning of the file path until the number of path
          LINE
        )
      end

      context "when a vendor directory is not checked in" do
        let(:project_name) { "go_sum" }

        it "excludes the vendored files" do
          paths = updater.updated_dependency_files.map(&:name)
          vendor_paths = paths.select { |path| path.start_with?("vendor") }
          expect(vendor_paths).to be_empty
        end
      end

      context "when there is a nested folder" do
        let(:project_name) { "nested_vendor" }
        let(:directory) { "nested" }

        let(:go_mod) do
          Dependabot::DependencyFile.new(
            name: "go.mod", content: go_mod_body, directory: directory
          )
        end
        let(:go_mod_body) do
          fixture("projects", project_name, directory, "go.mod")
        end

        let(:go_sum) do
          Dependabot::DependencyFile.new(
            name: "go.sum", content: go_sum_body, directory: directory
          )
        end
        let(:go_sum_body) do
          fixture("projects", project_name, directory, "go.sum")
        end

        it "vendors in the right directory" do
          ENV["GIT_AUTHOR_NAME"] = previous_git_author_name
          ENV["GIT_AUTHOR_EMAIL"] = previous_git_author_email
          ENV["GIT_COMMITTER_NAME"] = previous_git_committer_name
          ENV["GIT_COMMITTER_EMAIL"] = previous_git_committer_email
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

          updater.updated_dependency_files.map(&:directory).each do |dir|
            expect(dir).to eq("/nested")
          end
        end
      end
    end
  end
end
