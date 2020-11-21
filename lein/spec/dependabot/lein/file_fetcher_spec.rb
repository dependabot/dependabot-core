# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Lein::FileFetcher, :vcr do
  it_behaves_like "a dependency file fetcher"

  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "technomancy/leiningen",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    Dependabot::Lein::FileFetcher.new(source: source, credentials: credentials)
  end

  it "fetches the project.clj and generates the pom.xml" do
    expect(file_fetcher_instance.files.count).to eq(2)
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(project.clj pom.xml))
  end
end
