# typed: false
# frozen_string_literal: true

module NuGetSearchStubs
  def stub_no_search_results(name)
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/index.json")
      .to_return(status: 404, body: "")
  end

  def stub_registry_v3(name, versions)
    registration_json = registration_results(name, versions)
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/index.json")
      .to_return(status: 200, body: registration_json)
  end

  def stub_search_results_with_versions_v3(name, versions)
    stub_registry_v3(name, versions)
  end

  def registration_results(name, versions)
    page = {
      "@id": "https://api.nuget.org/v3/registration5-semver2/#{name}/index.json#page/PAGE1",
      "@type": "catalog:CatalogPage",
      "count" => versions.count,
      "items" => versions.map do |version|
        {
          "catalogEntry" => {
            "@type": "PackageDetails",
            "id" => name,
            "listed" => true,
            "version" => version
          }
        }
      end
    }
    pages = [page]
    response = {
      "@id": "https://api.nuget.org/v3/registration5-gz-semver2/#{name}/index.json",
      "count" => versions.count,
      "items" => pages
    }
    response.to_json
  end

  # rubocop:disable Metrics/MethodLength
  def search_results_with_versions_v2(name, versions)
    entries = versions.map do |version|
      xml = <<~XML
        <entry>
          <id>https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')</id>
          <category term="NuGetGallery.OData.V2FeedPackage" scheme="http://schemas.microsoft.com/ado/2007/08/dataservices/scheme" />
          <link rel="edit" href="https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')" />
          <link rel="self" href="https://www.nuget.org/api/v2/Packages(Id='#{name}',Version='#{version}')" />
          <title type="text">#{name}</title>
          <updated>2015-07-28T23:37:16Z</updated>
          <author>
              <name>FakeAuthor</name>
          </author>
          <content type="application/zip" src="https://www.nuget.org/api/v2/package/#{name}/#{version}" />
          <m:properties>
            <d:Id>#{name}</d:Id>
            <d:Version>#{version}</d:Version>
            <d:NormalizedVersion>#{version}</d:NormalizedVersion>
            <d:Authors>FakeAuthor</d:Authors>
            <d:Copyright>FakeCopyright</d:Copyright>
            <d:Created m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:Created>
            <d:Dependencies></d:Dependencies>
            <d:Description>FakeDescription</d:Description>
            <d:DownloadCount m:type="Edm.Int64">42</d:DownloadCount>
            <d:GalleryDetailsUrl>https://www.nuget.org/packages/#{name}/#{version}</d:GalleryDetailsUrl>
            <d:IconUrl m:null="true" />
            <d:IsLatestVersion m:type="Edm.Boolean">false</d:IsLatestVersion>
            <d:IsAbsoluteLatestVersion m:type="Edm.Boolean">false</d:IsAbsoluteLatestVersion>
            <d:IsPrerelease m:type="Edm.Boolean">false</d:IsPrerelease>
            <d:Language m:null="true" />
            <d:LastUpdated m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:LastUpdated>
            <d:Published m:type="Edm.DateTime">2015-07-28T23:37:16.85+00:00</d:Published>
            <d:PackageHash>FakeHash</d:PackageHash>
            <d:PackageHashAlgorithm>SHA512</d:PackageHashAlgorithm>
            <d:PackageSize m:type="Edm.Int64">42</d:PackageSize>
            <d:ProjectUrl>https://example.com/#{name}</d:ProjectUrl>
            <d:ReportAbuseUrl>https://example.com/#{name}</d:ReportAbuseUrl>
            <d:ReleaseNotes m:null="true" />
            <d:RequireLicenseAcceptance m:type="Edm.Boolean">false</d:RequireLicenseAcceptance>
            <d:Summary></d:Summary>
            <d:Tags></d:Tags>
            <d:Title>#{name}</d:Title>
            <d:VersionDownloadCount m:type="Edm.Int64">42</d:VersionDownloadCount>
            <d:MinClientVersion m:null="true" />
            <d:LastEdited m:type="Edm.DateTime">2018-12-08T05:53:10.917+00:00</d:LastEdited>
            <d:LicenseUrl>http://www.apache.org/licenses/LICENSE-2.0</d:LicenseUrl>
            <d:LicenseNames m:null="true" />
            <d:LicenseReportUrl m:null="true" />
          </m:properties>
        </entry>
      XML
      xml = xml.split("\n").map { |line| "  #{line}" }.join("\n")
      xml
    end.join("\n")
    xml = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xml:base="https://www.nuget.org/api/v2" xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
        xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
        <m:count>#{versions.length}</m:count>
        <id>http://schemas.datacontract.org/2004/07/</id>
        <title />
        <updated>2023-12-05T23:35:30Z</updated>
        <link rel="self" href="https://www.nuget.org/api/v2/Packages" />
        #{entries}
      </feed>
    XML
    xml
  end
  # rubocop:enable Metrics/MethodLength
end
