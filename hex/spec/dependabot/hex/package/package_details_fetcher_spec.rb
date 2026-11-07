# typed: strict
# frozen_string_literal: true

require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/hex/package/package_details_fetcher"
require "dependabot/hex/version"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "spec_helper"

RSpec.describe Dependabot::Hex::Package::PackageDetailsFetcher do
  extend T::Sig

  describe "#fetch_package_releases" do
    sig { returns(Dependabot::Hex::Package::PackageDetailsFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
    subject(:fetcher) { described_class.new(dependency: dependency) }

    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(Dependabot::Dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "hex"
      )
    end
    sig { returns(String) }
    let(:dependency_version) { "2.2.0" }
    sig { returns(String) }
    let(:dependency_name) { "hex/http" }
    sig { returns(T::Array[T::Hash[Symbol, Object]]) }
    let(:requirements) do
      [{
        file: "hex.json",
        requirement: string_req,
        groups: [],
        source: nil
      }]
    end
    sig { returns(String) }
    let(:string_req) { "1.0.0 <= v <= 2.2.0" }
    # rubocop:enable RSpec/ScatteredLet

    context "when the response is successful" do
      sig { returns(Excon::Response) }
      let(:response) do
        instance_double(
          Excon::Response,
          status: 200,
          body:
                fixture("package_fetch_response", "hex-parser.json")
        )
      end

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "returns an array of package releases" do
        releases = T.must(fetcher.fetch_package_releases)
        expect(releases.size).to eq(160)
        expect(releases.fetch(0).version.to_s).to eq("1.8.0-rc.3")
        expect(releases.fetch(0).released_at.to_s).to eq("2025-05-07 04:40:42 UTC")
        expect(releases.fetch(1).version.to_s).to eq("1.8.0-rc.2")
        expect(releases.fetch(1).released_at.to_s).to eq("2025-04-30 03:58:52 UTC")
      end
    end

    context "when the response is not successful" do
      sig { returns(Excon::Response) }
      let(:response) { instance_double(Excon::Response, status: 404, body: "[]") }

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "returns an empty array" do
        expect(fetcher.fetch_package_releases).to eq([])
      end
    end

    context "when the dependency has a hex package name alias" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pulsar",
          version: "2.8.7",
          requirements: [{
            file: "mix.exs",
            requirement: "~> 2.8.7",
            groups: [],
            source: nil
          }],
          package_manager: "hex",
          metadata: { hex_package: "pulsar_elixir" }
        )
      end

      sig { returns(Excon::Response) }
      let(:response) do
        instance_double(
          Excon::Response,
          status: 200,
          body:
                fixture("package_fetch_response", "hex-parser.json")
        )
      end
      # rubocop:enable RSpec/ScatteredLet

      before do
        allow(Dependabot::RegistryClient).to receive(:get).and_return(response)
      end

      it "queries the hex.pm API using the hex package name" do
        fetcher.fetch_package_releases
        expect(Dependabot::RegistryClient).to have_received(:get)
          .with(url: "https://hex.pm/api/packages/pulsar_elixir")
      end
    end
  end
end
