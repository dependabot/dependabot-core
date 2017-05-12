# frozen_string_literal: true
require "spec_helper"
require "octokit"
require "bump/repo"
require "bump/dependency_file_fetchers/base"

RSpec.shared_examples "a dependency file fetcher" do
  subject(:file_fetcher) do
    described_class.new(
      repo: repo,
      directory: directory,
      github_client: github_client
    )
  end
  let(:repo) { Bump::Repo.new(name: "gc/bump", language: nil, commit: nil) }
  let(:directory) { "/some/directory" }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  its(:required_files) { is_expected.to_not be_empty }

  describe "the class" do
    subject { described_class }
    let(:base_class) { Bump::DependencyFileFetchers::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
