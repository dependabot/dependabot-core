# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/cargo/package/package_details_fetcher"

RSpec.describe Dependabot::Cargo::Package::PackageDetailsFetcher do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Cargo::Package::PackageDetailsFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  sig { returns(String) }
  let(:dependency_name) { "es-entity" }
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "0.3.23",
      requirements: [{
        requirement: "==0.3.23",
        file: "crate.toml",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "cargo"
    )
  end
  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { [] }
  sig { returns(T::Array[Dependabot::Credential]) }
  let(:credentials) { [] }
  sig { returns(String) }
  let(:index_url) { "https://index.crates.io/es/-e/es-entity" }
  sig { returns(String) }
  let(:api_url) { "https://crates.io/api/v1/crates/es-entity" }
  sig { returns(String) }
  let(:index_response) do
    api_releases.map do |release|
      {
        "name" => dependency_name,
        "vers" => release.fetch("num"),
        "yanked" => release.fetch("yanked"),
        "pubtime" => release.fetch("created_at")
      }.to_json
    end.join("\n")
  end
  sig { returns(T::Array[T::Hash[String, T.anything]]) }
  let(:api_releases) do
    T.cast(
      JSON.parse(fixture("crates_io_responses", "package_fetcher.json")).fetch("versions"),
      T::Array[T::Hash[String, T.anything]]
    )
  end

  sig { returns(Dependabot::Package::PackageRelease) }
  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Cargo::Version.new("0.3.23"),
      released_at: Time.parse("2025-04-04 07:32:41.023326 UTC"),
      yanked: false,
      yanked_reason: nil,
      downloads: nil,
      url: nil,
      package_type: Dependabot::Cargo::Package::PackageDetailsFetcher::PACKAGE_TYPE,
      language: Dependabot::Package::PackageLanguage.new(
        name: "rust",
        version: nil,
        requirement: nil
      )
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#fetch" do
    sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
    subject(:fetch) { fetcher.fetch }

    context "with a valid response" do
      before do
        stub_request(:get, index_url)
          .to_return(
            status: 200,
            body: index_response,
            headers: { "Content-Type" => "text/plain" }
          )
      end

      it "fetches releases and their publication times from the index" do
        result = T.must(fetch)

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).not_to be_empty
        expect(a_request(:get, index_url)).to have_been_made.once
        expect(a_request(:get, api_url)).not_to have_been_made

        expect(result.releases.size).to be(24)

        first_result = T.must(result.releases.first)
        expect(first_result.version).to eq(latest_release.version)
        expect(first_result.released_at).to eq(latest_release.released_at)
        expect(first_result.yanked).to eq(latest_release.yanked)
        expect(first_result.yanked_reason).to eq(latest_release.yanked_reason)
        expect(first_result.downloads).to eq(latest_release.downloads)
        expect(first_result.url).to eq(latest_release.url)
        expect(first_result.package_type).to eq(latest_release.package_type)
        expect(T.must(first_result.language).name).to eq(T.must(latest_release.language).name)
        expect(T.must(first_result.language).requirement).to eq(T.must(latest_release.language).requirement)
      end
    end

    context "when a crates.io index record has no publication time" do
      let(:index_response) do
        <<~RESPONSE
          {"name":"es-entity","vers":"0.3.22","yanked":false,"pubtime":"2025-04-01T13:29:11Z"}
          {"name":"es-entity","vers":"0.3.23","yanked":false}
        RESPONSE
      end

      before do
        stub_request(:get, index_url).to_return(status: 200, body: index_response)
        stub_request(:get, api_url)
          .to_return(
            status: 200,
            body: fixture("crates_io_responses", "package_fetcher.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "falls back to the crates.io API publication time" do
        latest = T.must(T.must(fetch).releases.first)

        expect(latest.version).to eq(Dependabot::Cargo::Version.new("0.3.23"))
        expect(latest.released_at).to eq(Time.parse("2025-04-04 07:32:41.023326 UTC"))
        expect(a_request(:get, index_url)).to have_been_made.once
        expect(a_request(:get, api_url)).to have_been_made.once
      end
    end

    context "with a custom sparse registry" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "0.3.23",
          requirements: [{
            requirement: "==0.3.23",
            file: "crate.toml",
            groups: ["dependencies"],
            source: {
              type: "registry",
              name: "private-registry",
              index: "sparse+https://registry.example.com/index/"
            }
          }],
          package_manager: "cargo"
        )
      end
      let(:index_url) { "https://registry.example.com/index/es/-e/es-entity" }
      let(:index_response) do
        <<~RESPONSE
          {"name":"es-entity","vers":"0.3.22","yanked":false,"pubtime":"2025-04-01T13:29:11Z"}
          {"name":"es-entity","vers":"0.3.23","yanked":false,"pubtime":"2025-04-04T07:32:41Z"}
        RESPONSE
      end

      before do
        stub_request(:get, index_url).to_return(status: 200, body: index_response)
      end

      it "uses the registry index publication time without calling crates.io" do
        latest = T.must(T.must(fetch).releases.first)

        expect(latest.released_at).to eq(Time.parse("2025-04-04T07:32:41Z"))
        expect(a_request(:get, api_url)).not_to have_been_made
      end

      context "when pubtime is absent" do
        let(:index_response) do
          <<~RESPONSE
            {"name":"es-entity","vers":"0.3.22","yanked":false,"created_at":"2025-04-01T13:29:11Z"}
            {"name":"es-entity","vers":"0.3.23","yanked":false,"created_at":"2025-04-04T07:32:41Z"}
          RESPONSE
        end

        it "preserves the registry's existing created_at fallback" do
          latest = T.must(T.must(fetch).releases.first)

          expect(latest.released_at).to eq(Time.parse("2025-04-04T07:32:41Z"))
          expect(a_request(:get, api_url)).not_to have_been_made
        end
      end
    end
  end
end
