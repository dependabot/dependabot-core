# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/github_actions/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GithubActions::MetadataFinder do
  extend T::Sig

  sig { returns(Dependabot::GithubActions::MetadataFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
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
  sig { returns(T::Hash[T.any(String, Symbol), T.nilable(String)]) }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/actions/checkout",
      ref: "master",
      branch: nil
    }
  end
  sig { returns(String) }
  let(:dependency_name) { "actions/checkout" }
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source
      }],
      package_manager: "github_actions"
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    sig { returns(T.nilable(String)) }
    subject(:source_url) { finder.source_url }

    context "when dealing with a git source" do
      sig { returns(T::Hash[T.any(String, Symbol), T.nilable(String)]) }
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "master",
          branch: nil
        }
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }

      context "with string-keyed source details" do
        sig { returns(T::Hash[T.any(String, Symbol), T.nilable(String)]) }
        let(:dependency_source) do
          {
            "type" => "git",
            "url" => "https://github.com/actions/checkout",
            "ref" => "master",
            "branch" => nil
          }
        end

        it { is_expected.to eq("https://github.com/actions/checkout") }
      end

      context "when an earlier requirement has no source" do
        sig { returns(Dependabot::Dependency) }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: nil,
            requirements: [
              {
                requirement: nil,
                groups: [],
                file: ".github/workflows/workflow.yml",
                source: nil
              },
              {
                requirement: nil,
                groups: [],
                file: ".github/workflows/workflow.yml",
                source: dependency_source
              }
            ],
            package_manager: "github_actions"
          )
        end

        it { is_expected.to eq("https://github.com/actions/checkout") }
      end
    end

    context "when dealing with a subdependency" do
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: nil,
          requirements: [],
          package_manager: "github_actions"
        )
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }
    end

    context "when dealing with a subdependency on GHE" do
      # Simulates GitCommitChecker calling look_up_source with a subdependency
      # (empty requirements) when the job is configured with GHE source
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T::Array[Dependabot::Credential]) }
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "git_source",
            "host" => "mycompany.com",
            "username" => "x-access-token",
            "password" => "token"
          }
        )]
      end
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: nil,
          requirements: [],
          package_manager: "github_actions"
        )
      end
      # rubocop:enable RSpec/ScatteredLet

      before do
        stub_request(:get, "https://mycompany.com/status")
          .to_return(
            status: 200,
            headers: { "X-GitHub-Request-Id" => "12345" }
          )
      end

      it { is_expected.to eq("https://mycompany.com/actions/checkout") }
    end

    context "when dealing with a GitHub-hosted runner label" do
      let(:dependency_name) { "ubuntu" }
      let(:dependency_source) { { type: "runner" } }

      it "has no source, so no unrelated runner-images releases end up in the PR" do
        expect(source_url).to be_nil
      end

      it "links to the table of available runner images instead" do
        expect(finder.homepage_url).to eq("https://github.com/actions/runner-images#available-images")
      end
    end
  end
end
