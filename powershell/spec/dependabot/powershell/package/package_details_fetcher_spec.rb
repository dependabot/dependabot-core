# typed: false
# frozen_string_literal: true

require "cgi"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/powershell/package/package_details_fetcher"

RSpec.describe Dependabot::Powershell::Package::PackageDetailsFetcher do
  subject(:fetcher) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Pester",
      requirements: [{
        requirement: nil,
        groups: [],
        source: { type: "registry", url: "https://www.powershellgallery.com/api/v2" },
        file: "module.psd1"
      }],
      package_manager: "powershell"
    )
  end

  let(:find_packages_by_id_url) do
    "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27Pester%27"
  end

  def entry_xml(version:, published: "2023-05-01T12:00:00", prerelease: "false")
    <<~XML
      <entry>
        <content type="application/zip" src="https://www.powershellgallery.com/api/v2/package/Pester/#{version}" />
        <m:properties>
          <d:Version>#{version}</d:Version>
          <d:NormalizedVersion>#{version}</d:NormalizedVersion>
          <d:Published>#{published}</d:Published>
          <d:IsPrerelease>#{prerelease}</d:IsPrerelease>
          <d:IsLatestVersion>false</d:IsLatestVersion>
          <d:IsAbsoluteLatestVersion>false</d:IsAbsoluteLatestVersion>
        </m:properties>
      </entry>
    XML
  end

  def feed_xml(entries:, next_link: nil)
    link = next_link ? %(<link rel="next" href="#{CGI.escapeHTML(next_link)}" />) : ""
    <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
        #{link}
        #{entries.join("\n")}
      </feed>
    XML
  end

  describe "#fetch" do
    context "when the feed returns a single page of releases" do
      before do
        body = feed_xml(
          entries: [
            entry_xml(version: "5.4.0"),
            entry_xml(version: "5.3.3"),
            entry_xml(version: "5.5.0-beta1", prerelease: "true")
          ]
        )

        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: body)
      end

      it "returns a PackageDetails with all releases" do
        package_details = fetcher.fetch

        expect(package_details).to be_a(Dependabot::Package::PackageDetails)
        # Gem::Version normalises "5.5.0-beta1" to "5.5.0.pre.beta1" internally.
        expect(package_details.releases.map { |r| r.version.to_s }).to contain_exactly(
          "5.4.0", "5.3.3", "5.5.0.pre.beta1"
        )
      end

      it "sets the download url on each release" do
        package_details = fetcher.fetch
        release = package_details.releases.find { |r| r.version.to_s == "5.4.0" }

        expect(release.url).to eq("https://www.powershellgallery.com/api/v2/package/Pester/5.4.0")
      end

      it "sets released_at from the Published field" do
        package_details = fetcher.fetch
        release = package_details.releases.find { |r| r.version.to_s == "5.4.0" }

        expect(release.released_at).to eq(Time.parse("2023-05-01T12:00:00"))
      end

      it "does not mark ordinary releases as yanked" do
        package_details = fetcher.fetch

        expect(package_details.releases).to all(satisfy { |r| !r.yanked })
      end
    end

    context "when a release has the unlisted sentinel Published date" do
      before do
        body = feed_xml(
          entries: [
            entry_xml(version: "5.4.0"),
            entry_xml(version: "5.3.0", published: "1900-01-01T00:00:00")
          ]
        )

        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: body)
      end

      it "marks the release as yanked instead of relying on gallery flags" do
        package_details = fetcher.fetch
        unlisted_release = package_details.releases.find { |r| r.version.to_s == "5.3.0" }

        expect(unlisted_release.yanked).to be(true)
        expect(unlisted_release.released_at).to be_nil
      end

      it "leaves normally-published releases unyanked" do
        package_details = fetcher.fetch
        listed_release = package_details.releases.find { |r| r.version.to_s == "5.4.0" }

        expect(listed_release.yanked).to be(false)
      end
    end

    context "when the feed is paginated" do
      before do
        page1 = feed_xml(
          entries: [entry_xml(version: "5.4.0")],
          next_link: "#{find_packages_by_id_url}&$skip=1"
        )
        page2 = feed_xml(entries: [entry_xml(version: "5.3.3")])

        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: page1)
        stub_request(:get, "#{find_packages_by_id_url}&$skip=1")
          .to_return(status: 200, body: page2)
      end

      it "follows the next link and combines all pages of releases" do
        package_details = fetcher.fetch

        expect(package_details.releases.map { |r| r.version.to_s }).to contain_exactly("5.4.0", "5.3.3")
      end
    end

    context "when an entry has an invalid version" do
      before do
        body = feed_xml(
          entries: [
            entry_xml(version: "5.4.0"),
            entry_xml(version: "not-a-version")
          ]
        )

        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: body)
      end

      it "skips the invalid entry without raising" do
        package_details = fetcher.fetch

        expect(package_details.releases.map { |r| r.version.to_s }).to contain_exactly("5.4.0")
      end
    end

    context "when the registry request fails" do
      before do
        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 500, body: "")
      end

      it "returns an empty set of releases instead of raising" do
        package_details = fetcher.fetch

        expect(package_details.releases).to eq([])
      end
    end

    context "when the registry raises an error" do
      before do
        stub_request(:get, find_packages_by_id_url).to_raise(Excon::Error::Timeout)
      end

      it "rescues the error and returns an empty set of releases" do
        package_details = fetcher.fetch

        expect(package_details.releases).to eq([])
      end
    end
  end
end
