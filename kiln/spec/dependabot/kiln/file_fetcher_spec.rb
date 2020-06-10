# frozen_string_literal: true

require "spec_helper"
require "dependabot/kiln/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Kiln::FileFetcher, :vcr do
  it_behaves_like "a dependency file fetcher"

  let(:branch) { "master" }

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "releen/kiln-fixtures",
      directory: directory,
      branch: branch
    )
  end

  let(:directory) { "/" }

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: github_credentials)
  end


  context "for a kiln project" do
    context "without a Kilnfile" do
      let(:branch) { "without-Kilnfile" }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "without a Kilnfile.lock" do
      let(:branch) { "without-Kilnfile-lock" }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    it "fetches both Kilnfile and Kilnfile.lock" do
      expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Kilnfile.lock Kilnfile))
    end
  end
end
