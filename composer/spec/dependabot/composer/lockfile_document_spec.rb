# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/lockfile_document"

RSpec.describe Dependabot::Composer::LockfileDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "composer.lock", content: data.to_json) }
  let(:data) do
    {
      "plugin-api-version" => 1,
      "packages" => [
        { "name" => "vendor/package", "version" => 123, "source" => nil, "dist" => { "type" => "path" } },
        { "name" => "vendor/package", "version" => "v2", "source" => false },
        { "name" => false, "version" => [] }
      ],
      "packages-dev" => [
        {
          "name" => "vendor/package", "version" => "dev-branch",
          "source" => { "type" => "git", "reference" => "sha", "url" => false }
        }
      ]
    }
  end

  it "retains sections, duplicate occurrences, and integer version strings" do
    expect(document.packages("packages").map(&:name)).to eq(["vendor/package", "vendor/package", nil])
    expect(document.packages("packages").map(&:version)).to eq(["123", "v2", "[]"])
    expect(document.find_package("packages", "vendor/package").required_version).to eq("123")
    expect(document.find_package("packages-dev", "vendor/package").required_version).to eq("dev-branch")
    expect(document.plugin_api_version).to eq(1)
  end

  it "reads only consumed source fields and preserves opaque source metadata" do
    package = document.find_package("packages", "vendor/package")
    expect(package.path_source?).to be(true)

    git_package = document.find_package("packages-dev", "vendor/package")
    expect(git_package.path_source?).to be(false)
    expect(git_package.source_reference).to eq("sha")
    expect(git_package.git_source).to eq(type: "git", url: false)
  end

  context "with an invalid entry after a matching package" do
    let(:data) { { "packages" => [{ "name" => "vendor/package", "version" => "1" }, false] } }

    it "does not decode entries after the first match" do
      expect(document.find_package("packages", "vendor/package").version).to eq("1")
    end
  end

  context "with a missing version" do
    let(:data) { { "packages" => [{ "name" => "vendor/package" }] } }

    it "keeps optional enumeration distinct from required lookup" do
      package = document.find_package("packages", "vendor/package")
      expect(package.version).to be_nil
      expect { package.required_version }.to raise_error(KeyError)
    end
  end

  context "with malformed sections" do
    let(:data) { { "packages" => false, "packages-dev" => nil } }

    it "retains enumeration skips and lookup errors" do
      expect(document.packages("packages")).to eq([])
      expect(document.packages("packages-dev")).to eq([])
      expect(document.find_package("packages-dev", "vendor/package")).to be_nil
      expect { document.find_package("packages", "vendor/package") }.to raise_error(TypeError, /packages.*array/)
    end
  end

  describe "distribution reads" do
    let(:record) { { "dist" => { "type" => "path", "url" => "packages/one" }, "unknown" => [false, nil] } }
    let(:data) { { "packages" => [record, { "dist" => { "type" => "path", "url" => nil } }] } }

    it "keeps unknown fields and defers path URL validation until after matching" do
      package = document.find_path_package("packages", "packages/one")
      expect(package.to_manifest_json).to eq(record.to_json)
      expect(package.dist_url).to eq("packages/one")
      expect(package.dist_url_starts_with?("packages/")).to be(true)
      expect(document.path_packages("packages").last.dist_url_starts_with?("packages/")).to be(false)
    end

    context "with an invalid later record" do
      let(:data) { { "packages" => [record, false] } }

      it "stops at the first matching path" do
        expect(document.find_path_package("packages", "packages/one").to_manifest_json).to eq(record.to_json)
      end
    end
  end
end
