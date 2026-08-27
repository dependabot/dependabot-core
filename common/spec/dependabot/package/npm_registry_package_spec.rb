# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/npm_registry_package"

RSpec.describe Dependabot::Package::NpmRegistryPackage do
  describe ".from_json" do
    subject(:package) do
      described_class.from_json(
        JSON.dump(payload),
        &version_filter
      )
    end

    let(:version_filter) { ->(_version) { true } }

    let(:payload) do
      {
        "versions" => {
          "1.0.0" => {
            "deprecated" => "use 2.0.0",
            "engines" => { "node" => ">=18" },
            "repository" => { "type" => "git", "url" => "https://example.com/repo" },
            "dist" => { "tarball" => "https://example.com/package.tgz" }
          },
          "2.0.0" => {
            "repository" => "git+https://example.com/repo.git"
          }
        },
        "time" => {
          "1.0.0" => "2024-01-02T03:04:05Z",
          "created" => "2024-01-01T00:00:00Z"
        },
        "dist-tags" => {
          "latest" => "2.0.0",
          "next" => "3.0.0-beta.1"
        },
        "unknown" => true
      }
    end

    it "parses releases, timestamps, dist-tags, engines, and repository metadata" do
      first = package.releases.fetch("1.0.0")
      second = package.releases.fetch("2.0.0")

      expect(first).to have_attributes(
        version: "1.0.0",
        released_at: Time.utc(2024, 1, 2, 3, 4, 5),
        node_requirement: ">=18",
        package_type: "git"
      )
      expect(second).to have_attributes(
        version: "2.0.0",
        released_at: nil,
        node_requirement: nil,
        package_type: "git"
      )
      expect(package.dist_tags).to eq("latest" => "2.0.0", "next" => "3.0.0-beta.1")
    end

    it "preserves unknown release details" do
      expect(package.releases.fetch("1.0.0").details).to eq(payload.fetch("versions").fetch("1.0.0"))
    end

    context "with missing known fields" do
      let(:payload) { { "name" => "example" } }

      it "uses the existing empty and nil defaults" do
        expect(package.releases).to eq({})
        expect(package.dist_tags).to be_nil
      end
    end

    context "with unpublished time metadata" do
      let(:payload) do
        {
          "versions" => { "1.0.0" => {} },
          "time" => {
            "1.0.0" => "2024-01-01T00:00:00Z",
            "unpublished" => {
              "time" => "2024-01-02T00:00:00Z",
              "versions" => ["0.9.0"]
            }
          }
        }
      end

      it "ignores the metadata while parsing release timestamps" do
        expect(package.releases.fetch("1.0.0").released_at).to eq(Time.utc(2024, 1, 1))
      end
    end

    context "when the package is fully unpublished" do
      let(:payload) do
        {
          "time" => {
            "created" => "2024-01-01T00:00:00Z",
            "modified" => "2024-01-02T00:00:00Z",
            "unpublished" => {
              "time" => "2024-01-02T00:00:00Z",
              "versions" => ["1.0.0"]
            }
          }
        }
      end

      it "returns no releases" do
        expect(package.releases).to eq({})
      end
    end

    context "with an npm repository" do
      let(:payload) do
        {
          "versions" => {
            "1.0.0" => { "repository" => "https://example.com/package" },
            "2.0.0" => { "repository" => { "type" => "npm" } },
            "3.0.0" => { "repository" => { "url" => "git+https://example.com/package.git" } },
            "4.0.0" => {
              "repository" => {
                "type" => "npm",
                "url" => "git+https://example.com/package.git"
              }
            },
            "5.0.0" => {}
          }
        }
      end

      it "defaults package type to npm" do
        expect(package.releases.values.map(&:package_type)).to eq(%w(npm npm npm npm npm))
      end
    end

    context "with legacy engines metadata" do
      let(:payload) do
        {
          "versions" => {
            "1.0.0" => { "engines" => %w(node rhino) }
          }
        }
      end

      it "treats an engines array as having no Node requirement" do
        expect(package.releases.fetch("1.0.0").node_requirement).to be_nil
      end
    end

    context "when the version filter rejects a release" do
      let(:version_filter) { ->(_version) { false } }
      let(:payload) do
        {
          "versions" => {
            "not-a-version" => "invalid",
            "also-not-a-version" => {
              "engines" => "invalid",
              "repository" => []
            }
          },
          "time" => {
            "not-a-version" => 1,
            "also-not-a-version" => "not a timestamp",
            "created" => "2024-01-01T00:00:00Z"
          }
        }
      end

      it "skips the release before parsing its metadata" do
        expect(package.releases).to eq({})
      end
    end

    [
      [[], "npm registry package must be an object"],
      [{ "versions" => [] }, "versions must be an object"],
      [{ "versions" => { "1.0.0" => "invalid" } }, "version 1.0.0 details must be an object"],
      [{ "time" => [] }, "time must be an object"],
      [{ "versions" => { "1.0.0" => {} }, "time" => { "1.0.0" => 1 } }, "time values must be strings"],
      [{ "dist-tags" => [] }, "dist-tags must be an object"],
      [{ "dist-tags" => { "latest" => 1 } }, "dist-tags values must be strings"],
      [{
        "versions" => { "1.0.0" => { "engines" => "invalid" } }
      }, "version 1.0.0 engines must be an object"],
      [{
        "versions" => { "1.0.0" => { "engines" => { "node" => 18 } } }
      }, "version 1.0.0 engines.node must be a string"],
      [{
        "versions" => { "1.0.0" => { "repository" => [] } }
      }, "version 1.0.0 repository must be a string or object"],
      [{
        "versions" => { "1.0.0" => { "repository" => { "type" => 1 } } }
      }, "version 1.0.0 repository.type must be a string"]
    ].each do |invalid_payload, message|
      context "with #{message}" do
        let(:payload) { invalid_payload }

        it "raises an explicit type error" do
          expect { package }.to raise_error(TypeError, message)
        end
      end
    end

    context "with invalid JSON" do
      it "preserves the JSON parser error" do
        expect do
          described_class.from_json("{", &version_filter)
        end.to raise_error(JSON::ParserError)
      end
    end

    context "with an invalid timestamp" do
      let(:payload) do
        {
          "versions" => { "1.0.0" => {} },
          "time" => { "1.0.0" => "not a timestamp" }
        }
      end

      it "preserves the timestamp parse failure" do
        expect { package }.to raise_error(ArgumentError)
      end
    end
  end
end
