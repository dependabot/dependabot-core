# frozen_string_literal: true

require "spec_helper"
require "dependabot/ansible/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Ansible::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "Normo/ansible-test-project",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    Dependabot::Ansible::FileFetcher.new(source: source, credentials: credentials)
  end

  it "fetches the requirements.yml" do
    expect(file_fetcher_instance.files.count).to eq(1)
  end
end
