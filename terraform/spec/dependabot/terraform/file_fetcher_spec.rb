# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Terraform::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:directory) { "/" }
  let(:project_name) { "provider" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  after do
    FileUtils.rm_rf(repo_contents_path)
  end

  it_behaves_like "a dependency file fetcher"

  context "with Terraform files" do
    let(:project_name) { "versions_file" }

    it "fetches the Terraform files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(main.tf versions.tf))
    end
  end

  context "with a HCL based terragrunt file" do
    let(:project_name) { "terragrunt_hcl" }

    it "fetches the Terragrunt file" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(terragrunt.hcl))
    end
  end

  context "with a lockfile" do
    let(:project_name) { "terraform_lock_only" }

    it "fetches the lockfile" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.terraform.lock.hcl))
    end
  end

  context "when exclude-paths covers the whole directory" do
    let(:project_name) { "lockfile_in_subdirectory" }
    let(:directory) { "/frozen_project" }
    let(:file_fetcher_instance) do
      described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path).tap do |ff|
        ff.exclude_paths = ["frozen_project/**"]
      end
    end

    # The .tf files are dropped by the repo-contents filter, but the lockfile is fetched
    # by path rather than from the listing, so it has to be caught by the final filter.
    # If it survives, the directory reaches the parser holding a lockfile and no manifest,
    # and Terraform::FileParser#check_required_files raises "No Terraform configuration
    # file!" -- an unhandled error that aborts every other directory in the job too.
    it "excludes the lockfile as well as the manifests" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/nonexistent" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "when fetching nested local path modules" do
    let(:project_name) { "provider_with_multiple_local_path_modules" }

    it "fetches nested terraform files excluding symlinks" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(
          %w(.terraform.lock.hcl loader.tf providers.tf
             loader/providers.tf loader/projects.tf)
        )
    end
  end
end
