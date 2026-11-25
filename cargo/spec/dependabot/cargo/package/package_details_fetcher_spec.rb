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
  let(:json_url) { "https://crates.io/api/v1/crates/es-entity" }

  sig { returns(Dependabot::Package::PackageRelease) }
  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Cargo::Version.new("0.3.23"),
      released_at: Time.parse("2025-04-04 07:32:41.023326 UTC"),
      yanked: false,
      yanked_reason: nil,
      downloads: 345,
      url: "https://crates.io/api/v1/crates/es-entity/0.3.23/download",
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
        stub_request(:get, json_url)
          .to_return(
            status: 200,
            body: fixture("crates_io_responses", "package_fetcher.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches the latest version" do
        result = T.must(fetch)

        expect(result).to be_a(Dependabot::Package::PackageDetails)
        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once

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

    context "when crates.io returns an empty error response" do
      before do
        stub_request(:get, json_url).to_return(status: 503, body: "")
      end

      it "attaches only the registry host to the parse error" do
        expect { fetch }.to raise_error(JSON::ParserError) do |error|
          context = T.must(Dependabot::ErrorReportContext.build(error: error))
          expect(context).to include("host" => "crates.io", "http-status" => 503)
          expect(context.values.join).not_to include("es-entity")
        end
      end
    end

    context "with a dependency from a private registry" do
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "0.3.23",
          requirements: [{
            requirement: "==0.3.23",
            file: "Cargo.toml",
            groups: ["dependencies"],
            source: { type: "registry", name: "my-registry", index: "https://private.example.com/index" }
          }],
          package_manager: "cargo"
        )
      end

      context "when the registry rejects the credentials" do
        before do
          stub_request(:get, "https://private.example.com/index/es/-e/es-entity").to_return(
            status: 403,
            body: "Forbidden"
          )
        end

        it "raises a PrivateSourceAuthenticationFailure for the registry" do
          expect { fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(T.cast(error, Dependabot::PrivateSourceAuthenticationFailure).source)
              .to eq("https://private.example.com/index")
          end
        end
      end

      context "when the registry returns a server error" do
        before do
          stub_request(:get, "https://private.example.com/index/es/-e/es-entity").to_return(status: 500, body: "")
        end

        it "raises a PrivateSourceBadResponse" do
          expect { fetch }.to raise_error(Dependabot::PrivateSourceBadResponse)
        end
      end
    end
  end
end
