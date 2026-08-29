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
  let(:manifest_url) do
    "https://www.powershellgallery.com/packages/Pester/5.4.0/Content/Pester.psd1"
  end
  let(:mar_tags_url) { "https://mcr.microsoft.com/v2/psresource/#{dependency.name.downcase}/tags/list" }

  before do
    stub_request(:get, mar_tags_url).to_return(status: 404, body: "")
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
    context "when the module is available from Microsoft Artifact Registry" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Az.Accounts",
          requirements: [{
            requirement: "= 4.0.0",
            groups: [],
            source: { type: "registry", url: "https://www.powershellgallery.com/api/v2" },
            file: "module.psd1"
          }],
          package_manager: "powershell"
        )
      end

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 200,
          body: JSON.dump(
            "name" => "psresource/az.accounts",
            "tags" => ["4.0.0", "5.5.2", "5.6.0-preview", "not-a-version"]
          )
        )
      end

      it "uses the lowercased MAR repository as the authoritative source" do
        releases = fetcher.fetch.releases

        expect(releases.map { |release| release.version.to_s }).to contain_exactly(
          "4.0.0", "5.5.2", "5.6.0-preview"
        )
        expect(releases).to all(satisfy { |release| release.released_at.nil? })
        expect(fetcher.selected_source).to eq(
          type: "registry",
          url: "https://mcr.microsoft.com"
        )
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end

      it "extracts the module GUID from the selected MAR manifest" do
        metadata = {
          "ModuleVersion" => "5.5.2",
          "GUID" => "17a2feff-488b-47f9-8729-e2cec094624c"
        }
        stub_request(
          :get,
          "https://mcr.microsoft.com/v2/psresource/az.accounts/manifests/5.5.2"
        ).to_return(
          status: 200,
          body: JSON.dump(
            "schemaVersion" => 2,
            "mediaType" => "application/vnd.oci.image.manifest.v1+json",
            "config" => {
              "mediaType" => "application/vnd.oci.image.config.v1+json",
              "digest" => "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "size" => 0
            },
            "layers" => [{
              "mediaType" => "application/vnd.oci.image.layer.v1.tar+gzip",
              "digest" => "sha256:4465339b2c52cb19d0cb6ee16467076cd7f32633e9195df675373eb81e0e8cca",
              "size" => 10_201_874,
              "annotations" => { "metadata" => JSON.dump(metadata) }
            }]
          ),
          headers: { "Content-Type" => "application/vnd.oci.image.manifest.v1+json" }
        )

        fetcher.fetch

        expect(fetcher.manifest_guid_for("5.5.2")).to eq("17a2feff-488b-47f9-8729-e2cec094624c")
      end

      context "when the tags response is paginated" do
        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: {
              "Link" => '</v2/psresource/az.accounts/tags/list?last=4.0.0>; rel="next"'
            }
          )
          stub_request(:get, "#{mar_tags_url}?last=4.0.0").to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["5.5.2"])
          )
        end

        it "combines every page before selecting releases" do
          expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("4.0.0", "5.5.2")
        end
      end

      context "when a later tags page is not found" do
        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: {
              "Link" => '</v2/psresource/az.accounts/tags/list?last=4.0.0>; rel="next"'
            }
          )
          stub_request(:get, "#{mar_tags_url}?last=4.0.0").to_return(status: 404, body: "")
        end

        it "discards partial MAR results without falling back to the PowerShell Gallery" do
          expect(fetcher.fetch.releases).to eq([])
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end

      context "when the tags response has a malformed pagination link" do
        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => "not-a-link" }
          )
        end

        it "returns no releases without falling back to the PowerShell Gallery" do
          expect(fetcher.fetch.releases).to eq([])
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end

      context "when the tags response repeats a pagination link" do
        before do
          repeated_url = "#{mar_tags_url}?last=4.0.0"
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => '</v2/psresource/az.accounts/tags/list?last=4.0.0>; rel="next"' }
          )
          stub_request(:get, repeated_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["5.5.2"]),
            headers: { "Link" => '</v2/psresource/az.accounts/tags/list?last=4.0.0>; rel="next"' }
          )
        end

        it "returns no releases instead of looping or falling back" do
          expect(fetcher.fetch.releases).to eq([])
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end
    end

    context "when the module is absent from Microsoft Artifact Registry" do
      before do
        body = feed_xml(entries: [entry_xml(version: "5.4.0")])
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "falls back to the PowerShell Gallery" do
        expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("5.4.0")
        expect(fetcher.selected_source).to eq(
          type: "registry",
          url: "https://www.powershellgallery.com/api/v2"
        )
        expect(a_request(:get, mar_tags_url)).to have_been_made.once
        expect(a_request(:get, find_packages_by_id_url)).to have_been_made.once
      end
    end

    context "when Microsoft Artifact Registry fails after finding the repository" do
      before do
        stub_request(:get, mar_tags_url).to_return(status: 500, body: "")
      end

      it "does not downgrade to the PowerShell Gallery" do
        expect(fetcher.fetch.releases).to eq([])
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry returns malformed JSON data" do
      before do
        stub_request(:get, mar_tags_url).to_return(status: 200, body: "null")
      end

      it "returns no releases without falling back to the PowerShell Gallery" do
        expect(fetcher.fetch.releases).to eq([])
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

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
        expect(package_details.releases.map { |r| r.version.to_s }).to contain_exactly(
          "5.4.0", "5.3.3", "5.5.0-beta1"
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

      describe "#manifest_guid_for" do
        it "extracts the GUID from the selected release's module manifest" do
          stub_request(:get, manifest_url).to_return(
            status: 200,
            body: <<~HTML
              <html><body>
                <span>GUID</span>&nbsp;&nbsp;<span>=</span>&nbsp;
                <span>'a699dea5-2c73-4616-a270-1f7abb777e71'</span>
              </body></html>
            HTML
          )

          expect(fetcher.manifest_guid_for("5.4.0")).to eq("a699dea5-2c73-4616-a270-1f7abb777e71")
        end

        it "returns nil when the module manifest has no GUID" do
          stub_request(:get, manifest_url).to_return(status: 200, body: "@{ ModuleVersion = '5.4.0' }")

          expect(fetcher.manifest_guid_for("5.4.0")).to be_nil
        end

        it "returns nil when the module manifest cannot be fetched" do
          stub_request(:get, manifest_url).to_return(status: 404, body: "")

          expect(fetcher.manifest_guid_for("5.4.0")).to be_nil
        end
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

    context "when the page limit is reached with another page pending" do
      before do
        stub_const("#{described_class}::MAX_PAGES", 1)
        page1 = feed_xml(
          entries: [entry_xml(version: "5.4.0")],
          next_link: "#{find_packages_by_id_url}&$skip=1"
        )
        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: page1)
      end

      it "discards partial releases" do
        expect(fetcher.fetch.releases).to eq([])
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

    context "when a later page of a paginated feed fails" do
      before do
        page1 = feed_xml(
          entries: [entry_xml(version: "5.4.0")],
          next_link: "#{find_packages_by_id_url}&$skip=1"
        )

        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: page1)
        stub_request(:get, "#{find_packages_by_id_url}&$skip=1")
          .to_return(status: 500, body: "")
      end

      it "discards the first page's releases instead of returning an incomplete set" do
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
