require "dependabot/update_checkers/version_filters"
require "dependabot/package/package_release"
require "rspec"

RSpec.describe Dependabot::UpdateCheckers::VersionFilters do
  describe ".filter_vulnerable_versions" do
    let(:security_advisory) { instance_double(Dependabot::SecurityAdvisory) }
    let(:versions_array) { [] }
    let(:vulnerable_version) { Dependabot::Version.new("1.0.0") }
    let(:safe_version) { Dependabot::Version.new("2.0.0") }

    before do
      allow(security_advisory).to receive(:vulnerable?).and_return(false)
    end

    context "when version is a Gem::Version" do
      it "filters out vulnerable versions" do
        allow(security_advisory).to receive(:vulnerable?).with(vulnerable_version).and_return(true)

        versions_array = [vulnerable_version, safe_version]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result).to contain_exactly(safe_version)
      end

      it "keeps safe versions" do
        allow(security_advisory).to receive(:vulnerable?).with(safe_version).and_return(false)

        versions_array = [vulnerable_version, safe_version]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result).to contain_exactly(safe_version, vulnerable_version)
      end
    end

    context "when version is a PackageRelease" do
      let(:package_release) { Dependabot::Package::PackageRelease.new(version: vulnerable_version) }

      it "filters out vulnerable package releases" do
        allow(security_advisory).to receive(:vulnerable?).with(vulnerable_version).and_return(true)

        versions_array = [package_release, Dependabot::Package::PackageRelease.new(version: safe_version)]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result.size).to eq(1)
        expect(result.first.version).to eq(safe_version)
      end

      it "keeps safe package releases" do
        allow(security_advisory).to receive(:vulnerable?).with(safe_version).and_return(false)

        versions_array = [package_release, Dependabot::Package::PackageRelease.new(version: safe_version)]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result.size).to eq(2)
        expect(result.map(&:version)).to contain_exactly(vulnerable_version, safe_version)
      end
    end

    context "when version is a Hash with :version key" do
      let(:vulnerable_version_hash) { { version: vulnerable_version } }
      let(:safe_version_hash) { { version: safe_version } }

      it "filters out vulnerable hash versions" do
        allow(security_advisory).to receive(:vulnerable?).with(vulnerable_version).and_return(true)

        versions_array = [vulnerable_version_hash, safe_version_hash]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result).to contain_exactly(safe_version_hash)
      end

      it "keeps safe hash versions" do
        allow(security_advisory).to receive(:vulnerable?).with(safe_version).and_return(false)

        versions_array = [vulnerable_version_hash, safe_version_hash]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result).to contain_exactly(vulnerable_version_hash, safe_version_hash)
      end
    end

    context "when there are no security advisories" do
      it "does not filter any versions" do
        versions_array = [vulnerable_version, safe_version]
        result = described_class.filter_vulnerable_versions(versions_array, [])

        expect(result).to contain_exactly(vulnerable_version, safe_version)
      end
    end

    context "when all versions are vulnerable" do
      it "filters all versions" do
        allow(security_advisory).to receive(:vulnerable?).with(vulnerable_version).and_return(true)
        allow(security_advisory).to receive(:vulnerable?).with(safe_version).and_return(true)

        versions_array = [vulnerable_version, safe_version]
        result = described_class.filter_vulnerable_versions(versions_array, [security_advisory])

        expect(result).to be_empty
      end
    end
  end
end
