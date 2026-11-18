# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Pub::FileFetcher do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  sig { returns(String) }
  let(:directory) { "/" }
  sig { returns(String) }
  let(:project_name) { "pinned_version" }
  sig { returns(Dependabot::Pub::FileFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  sig { returns(Dependabot::Source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  after do
    FileUtils.rm_rf(repo_contents_path)
  end

  it_behaves_like "a dependency file fetcher"

  context "with pubspec.yaml and pubspec.lock" do
    it "fetches the files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(pubspec.yaml pubspec.lock))
    end
  end

  context "when dealing with a mono-repo" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:project_name) { "mono_repo" }
    sig { returns(String) }
    let(:directory) { "/main" }
    # rubocop:enable RSpec/ScatteredLet

    it "fetches the files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(pubspec.yaml pubspec.lock ../dep/pubspec.yaml))
    end
  end

  context "when dealing with a mono-repo with no pubspec.lock" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:project_name) { "no_lockfile" }
    sig { returns(String) }
    let(:directory) { "/main" }
    # rubocop:enable RSpec/ScatteredLet

    it "fetches the files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(pubspec.yaml ../dep/pubspec.yaml))
    end
  end

  context "when dealing with a pub workspace" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:project_name) { "can_update_workspace" }
    sig { returns(String) }
    let(:directory) { "/" }
    # rubocop:enable RSpec/ScatteredLet

    it "fetches the files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(app/pubspec.yaml pubspec.lock pubspec.yaml))
    end
  end
end
