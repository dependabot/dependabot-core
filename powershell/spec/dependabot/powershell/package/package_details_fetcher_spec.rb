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
  let(:mar_manifest_url) do
    "https://mcr.microsoft.com/v2/psresource/#{dependency.name.downcase}/manifests/5.4.0"
  end

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

      context "when the tags response uses a same-origin absolute pagination URL" do
        let(:next_page_url) { "#{mar_tags_url}?last=4.0.0" }

        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => "<#{next_page_url}>; rel=\"next\"" }
          )
          stub_request(:get, next_page_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["5.5.2"])
          )
        end

        it "follows the link and combines every page" do
          expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("4.0.0", "5.5.2")
        end
      end

      context "when the tags response uses an explicit HTTPS default port" do
        let(:next_page_url) do
          "https://mcr.microsoft.com:443/v2/psresource/az.accounts/tags/list?last=4.0.0"
        end

        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => "<#{next_page_url}>; rel=\"next\"" }
          )
          stub_request(:get, next_page_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["5.5.2"])
          )
        end

        it "follows the link and combines every page" do
          expect(fetcher.fetch.releases.map { |release| release.version.to_s }).to contain_exactly("4.0.0", "5.5.2")
        end
      end

      {
        "scheme-relative URL" => [
          "//mcr.microsoft.com/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET",
          "https://mcr.microsoft.com/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET"
        ],
        "HTTP URL" => [
          "http://mcr.microsoft.com/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET",
          "http://mcr.microsoft.com/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET"
        ],
        "external host" => [
          "https://registry.example/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET",
          "https://registry.example/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET"
        ],
        "subdomain host" => [
          "https://mcr.microsoft.com.registry.example/v2/psresource/az.accounts/tags/list?" \
          "access_token=MAR_LINK_SECRET",
          "https://mcr.microsoft.com.registry.example/v2/psresource/az.accounts/tags/list?" \
          "access_token=MAR_LINK_SECRET"
        ],
        "credentialed URL" => [
          "https://user:MAR_LINK_SECRET@mcr.microsoft.com/v2/psresource/az.accounts/tags/list",
          "https://user:MAR_LINK_SECRET@mcr.microsoft.com/v2/psresource/az.accounts/tags/list"
        ],
        "alternate port" => [
          "https://mcr.microsoft.com:444/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET",
          "https://mcr.microsoft.com:444/v2/psresource/az.accounts/tags/list?access_token=MAR_LINK_SECRET"
        ],
        "wrong path" => [
          "https://mcr.microsoft.com/v2/psresource/other/tags/list?access_token=MAR_LINK_SECRET",
          "https://mcr.microsoft.com/v2/psresource/other/tags/list?access_token=MAR_LINK_SECRET"
        ]
      }.each do |description, (link_url, requested_url)|
        context "when the tags response uses a #{description}" do
          let(:secret) { "MAR_LINK_SECRET" }

          before do
            stub_request(:get, mar_tags_url).to_return(
              status: 200,
              body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
              headers: { "Link" => "<#{link_url}>; rel=\"next\"" }
            )
            stub_request(:get, requested_url).to_return(
              status: 200,
              body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["5.5.2"])
            )
          end

          it "rejects the link without making the request or exposing its contents" do
            expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to include("Microsoft Artifact Registry", "Az.Accounts", "pagination")
              expect(error.full_message).not_to include(secret, "access_token")
              expect(error.cause).to be_nil
            end
            expect(a_request(:get, requested_url)).not_to have_been_made
            expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
          end
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

        it "raises a registry error without falling back to the PowerShell Gallery" do
          expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
            expect(error.status).to eq(404)
          end
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

        it "raises a resolvability error without falling back to the PowerShell Gallery" do
          expect { fetcher.fetch }.to raise_error(
            Dependabot::DependencyFileNotResolvable,
            /Microsoft Artifact Registry.*Az\.Accounts.*pagination/i
          )
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end

      context "when the tags response has an invalid UTF-8 pagination header" do
        before do
          link = "</v2/psresource/az.accounts/tags/list?last=4.0.0\xFF>; rel=\"next\""
                 .b.force_encoding(Encoding::UTF_8)
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => link }
          )
        end

        it "raises a sanitized resolvability error without falling back" do
          expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Microsoft Artifact Registry", "Az.Accounts", "pagination")
            expect(error.cause).to be_nil
          end
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end

      context "when the tags response has a secret-bearing invalid pagination URL" do
        let(:secret) { "MAR_URL_SECRET" }

        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: {
              "Link" => "<https://mcr.microsoft.com/%ZZ?access_token=#{secret}>; rel=\"next\""
            }
          )
        end

        it "raises a sanitized resolvability error without falling back" do
          expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Microsoft Artifact Registry", "Az.Accounts", "pagination")
            expect(error.full_message).not_to include(secret, "access_token")
            expect(error.cause).to be_nil
          end
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end

      context "when the tags response has a secret-bearing invalid URI component" do
        let(:secret) { "MAR_COMPONENT_SECRET" }

        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 200,
            body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0"]),
            headers: { "Link" => "<mailto:#{secret}>; rel=\"next\"" }
          )
        end

        it "raises a sanitized resolvability error without falling back" do
          expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Microsoft Artifact Registry", "Az.Accounts", "pagination")
            expect(error.full_message).not_to include(secret)
            expect(error.cause).to be_nil
          end
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

        it "raises a resolvability error instead of looping or falling back" do
          expect { fetcher.fetch }.to raise_error(
            Dependabot::DependencyFileNotResolvable,
            /Microsoft Artifact Registry.*Az\.Accounts.*pagination/i
          )
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

      it "raises a registry error without downgrading to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(500)
          expect(error.message).to include("Microsoft Artifact Registry", "Pester")
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry authentication fails" do
      before do
        stub_request(:get, mar_tags_url).to_raise(DockerRegistry2::RegistryAuthenticationException)
      end

      it "raises a typed authentication error without downgrading to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when the Microsoft Artifact Registry token endpoint is not found" do
      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 401,
          headers: {
            "Www-Authenticate" =>
              'Bearer realm="https://mcr.microsoft.com/oauth2/token",service="mcr.microsoft.com",' \
              'scope="repository:psresource/pester:pull"'
          }
        )
        stub_request(:get, %r{\Ahttps://mcr\.microsoft\.com/oauth2/token}).to_return(status: 404, body: "")
      end

      it "raises an authentication error instead of treating the module as absent" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    {
      "uses HTTP" => [
        "http://mcr.microsoft.com/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttp://mcr\.microsoft\.com}
      ],
      "uses a loopback address" => [
        "https://127.0.0.1/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttps://127\.0\.0\.1}
      ],
      "uses a private address" => [
        "https://10.0.0.1/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttps://10\.0\.0\.1}
      ],
      "uses an external host" => [
        "https://registry.example/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttps://registry\.example}
      ],
      "uses an MCR subdomain" => [
        "https://token.mcr.microsoft.com/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttps://token\.mcr\.microsoft\.com}
      ],
      "contains credentials" => [
        "https://user:MAR_REALM_SECRET@mcr.microsoft.com/oauth2/token",
        %r{\Ahttps://user:MAR_REALM_SECRET@mcr\.microsoft\.com}
      ],
      "uses an alternate port" => [
        "https://mcr.microsoft.com:8443/oauth2/token?access_token=MAR_REALM_SECRET",
        %r{\Ahttps://mcr\.microsoft\.com:8443}
      ],
      "uses the wrong path" => [
        "https://mcr.microsoft.com/oauth2/MAR_REALM_SECRET",
        %r{\Ahttps://mcr\.microsoft\.com/oauth2/MAR_REALM_SECRET}
      ]
    }.each do |description, (realm, outbound_request)|
      context "when the Microsoft Artifact Registry bearer realm #{description}" do
        before do
          stub_request(:get, mar_tags_url).to_return(
            status: 401,
            headers: {
              "Www-Authenticate" =>
                ["Bearer", "realm=\"#{realm}\",service=\"mcr.microsoft.com\""].join(" ")
            }
          )
        end

        it "fails closed without requesting the realm or exposing it" do
          expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("https://mcr.microsoft.com")
            expect(error.full_message).not_to include("MAR_REALM_SECRET", "access_token")
            expect(error.cause).to be_nil
          end
          expect(a_request(:get, outbound_request)).not_to have_been_made
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end
    end

    context "when the Microsoft Artifact Registry bearer realm is malformed" do
      let(:secret) { "MAR_REALM_SECRET" }

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 401,
          headers: {
            "Www-Authenticate" =>
              ["Bearer", "realm=\"https://mcr.microsoft.com/%ZZ?access_token=#{secret}\"," \
                         "service=\"mcr.microsoft.com\""].join(" ")
          }
        )
      end

      it "raises a sanitized authentication error instead of exposing the realm" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
          expect(error.full_message).not_to include(secret, "access_token")
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when the Microsoft Artifact Registry bearer realm has an invalid URI component" do
      let(:secret) { "MAR_REALM_COMPONENT_SECRET" }

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 401,
          headers: {
            "Www-Authenticate" =>
              ["Bearer", "realm=\"mailto:#{secret}\",service=\"mcr.microsoft.com\""].join(" ")
          }
        )
      end

      it "raises a sanitized authentication error instead of exposing the realm" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
          expect(error.full_message).not_to include(secret)
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when the Microsoft Artifact Registry bearer realm has invalid UTF-8" do
      let(:secret) { "MAR_REALM_ENCODING_SECRET" }

      before do
        realm = "https://mcr.microsoft.com/oauth2/token?access_token=#{secret}\xFF".b.force_encoding(Encoding::UTF_8)
        stub_request(:get, mar_tags_url).to_return(
          status: 401,
          headers: {
            "Www-Authenticate" =>
              ["Bearer", "realm=\"#{realm}\",service=\"mcr.microsoft.com\""].join(" ")
          }
        )
      end

      it "raises a sanitized authentication error without requesting the realm" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
          expect(error.full_message).not_to include(secret, "access_token")
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, /MAR_REALM_ENCODING_SECRET/)).not_to have_been_made
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    {
      "an external host" => [
        "https://redirect.example/tags?access_token=MAR_REDIRECT_SECRET",
        %r{\Ahttps://redirect\.example}
      ],
      "a loopback address" => [
        "https://127.0.0.1/tags?access_token=MAR_REDIRECT_SECRET",
        %r{\Ahttps://127\.0\.0\.1}
      ],
      "a private address" => [
        "https://10.0.0.1/tags?access_token=MAR_REDIRECT_SECRET",
        %r{\Ahttps://10\.0\.0\.1}
      ],
      "a credentialed URL" => [
        "https://user:MAR_REDIRECT_SECRET@redirect.example/tags",
        %r{\Ahttps://user:MAR_REDIRECT_SECRET@redirect\.example}
      ]
    }.each do |description, (location, outbound_request)|
      context "when the Microsoft Artifact Registry tags endpoint redirects to #{description}" do
        before do
          stub_request(:get, mar_tags_url).to_return(status: 302, headers: { "Location" => location })
        end

        it "raises a sanitized registry error without following or falling back" do
          expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
            expect(error.status).to eq(302)
            expect(error.message).to include("Microsoft Artifact Registry", "Pester")
            expect(error.full_message).not_to include("MAR_REDIRECT_SECRET", "access_token")
            expect(error.cause).to be_nil
          end
          expect(a_request(:get, outbound_request)).not_to have_been_made
          expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
        end
      end
    end

    context "when the Microsoft Artifact Registry token endpoint redirects externally" do
      let(:token_url) { "https://mcr.microsoft.com/oauth2/token" }
      let(:redirect_url) { "https://redirect.example/token?access_token=MAR_TOKEN_REDIRECT_SECRET" }

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 401,
          headers: {
            "Www-Authenticate" =>
              'Bearer realm="https://mcr.microsoft.com/oauth2/token",service="mcr.microsoft.com"'
          }
        )
        stub_request(:get, /\A#{Regexp.escape(token_url)}/).to_return(
          status: 302,
          headers: { "Location" => redirect_url }
        )
      end

      it "raises a sanitized registry error without following or falling back" do
        expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(302)
          expect(error.message).to include("Microsoft Artifact Registry", "Pester")
          expect(error.full_message).not_to include("MAR_TOKEN_REDIRECT_SECRET", "access_token")
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, %r{\Ahttps://redirect\.example})).not_to have_been_made
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry times out" do
      before do
        stub_request(:get, mar_tags_url).to_raise(DockerRegistry2::RegistryUnknownException)
      end

      it "raises a typed timeout error without downgrading to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry has a certificate failure" do
      before do
        stub_request(:get, mar_tags_url).to_raise(DockerRegistry2::RegistrySSLException)
      end

      it "raises a typed certificate error without downgrading to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceCertificateFailure) do |error|
          expect(error.source).to eq("https://mcr.microsoft.com")
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when the selected Microsoft Artifact Registry manifest redirects externally" do
      let(:redirect_url) do
        "https://redirect.example/manifest?access_token=MAR_MANIFEST_REDIRECT_SECRET"
      end

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 200,
          body: JSON.dump("name" => "psresource/pester", "tags" => ["5.4.0"])
        )
        stub_request(:get, mar_manifest_url).to_return(
          status: 302,
          headers: { "Location" => redirect_url }
        )
      end

      it "raises a sanitized registry error without following or falling back" do
        fetcher.fetch

        expect { fetcher.manifest_guid_for("5.4.0") }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(302)
          expect(error.message).to include("Microsoft Artifact Registry", "Pester")
          expect(error.full_message).not_to include("MAR_MANIFEST_REDIRECT_SECRET", "access_token")
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, %r{\Ahttps://redirect\.example})).not_to have_been_made
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry returns malformed JSON data" do
      let(:secret) { "MAR_JSON_SECRET" }

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 200,
          body: %({"access_token":#{secret}})
        )
      end

      it "raises a sanitized resolvability error without falling back to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("Microsoft Artifact Registry", "Pester")
          expect(error.full_message).not_to include(secret, "access_token")
          expect(error.cause).to be_nil
        end
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry returns an invalid document shape" do
      before do
        stub_request(:get, mar_tags_url).to_return(status: 200, body: "null")
      end

      it "raises a resolvability error without falling back to the PowerShell Gallery" do
        expect { fetcher.fetch }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /Microsoft Artifact Registry.*Pester/i
        )
        expect(a_request(:get, find_packages_by_id_url)).not_to have_been_made
      end
    end

    context "when Microsoft Artifact Registry returns a tag with invalid UTF-8" do
      before do
        body = %({"name":"psresource/pester","tags":["5.4.0\xFF"]}).b.force_encoding(Encoding::UTF_8)
        stub_request(:get, mar_tags_url).to_return(status: 200, body: body)
      end

      it "raises a sanitized resolvability error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("Microsoft Artifact Registry", "Pester")
          expect(error.cause).to be_nil
        end
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

        it "raises when the module manifest has no GUID" do
          stub_request(:get, manifest_url).to_return(status: 200, body: "@{ ModuleVersion = '5.4.0' }")

          expect { fetcher.manifest_guid_for("5.4.0") }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end

        it "raises when the module manifest cannot be fetched" do
          stub_request(:get, manifest_url).to_return(status: 404, body: "")

          expect { fetcher.manifest_guid_for("5.4.0") }
            .to raise_error(Dependabot::RegistryError) do |error|
              expect(error.status).to eq(404)
            end
        end

        it "raises when the module manifest is malformed" do
          stub_request(:get, manifest_url)
            .to_return(status: 200, body: "@{ GUID = 'a699dea5-2c73-4616-a270-1f7abb777e71 }")

          expect { fetcher.manifest_guid_for("5.4.0") }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end

        it "raises when the module manifest has an invalid GUID" do
          stub_request(:get, manifest_url).to_return(status: 200, body: "@{ GUID = 'not-a-guid' }")

          expect { fetcher.manifest_guid_for("5.4.0") }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end
      end
    end

    context "when a valid feed contains no releases" do
      before do
        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: feed_xml(entries: []))
      end

      it "returns an empty release set for an absent package" do
        expect(fetcher.fetch.releases).to be_empty
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

      it "raises rather than returning an incomplete release set" do
        expect { fetcher.fetch }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /PowerShell Gallery.*Pester.*page limit/i
        )
      end
    end

    context "when the feed contains malformed XML" do
      let(:secret) { "GALLERY_XML_SECRET" }

      before do
        stub_request(:get, find_packages_by_id_url)
          .to_return(status: 200, body: "<feed><#{secret}></feed>")
      end

      it "raises a sanitized resolvability error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("PowerShell Gallery", "XML", "Pester")
          expect(error.full_message).not_to include(secret)
          expect(error.cause).to be_nil
        end
      end
    end

    context "when a next-page link has no href" do
      before do
        body = <<~XML
          <feed xmlns="http://www.w3.org/2005/Atom">
            <link rel="next" />
          </feed>
        XML
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "raises rather than treating an incomplete feed as complete" do
        expect { fetcher.fetch }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /PowerShell Gallery.*Pester.*pagination/i
        )
      end
    end

    context "when a next-page link contains a secret-bearing invalid URL" do
      let(:secret) { "GALLERY_URL_SECRET" }

      before do
        body = feed_xml(
          entries: [entry_xml(version: "5.4.0")],
          next_link: "https://www.powershellgallery.com/%ZZ?access_token=#{secret}"
        )
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "raises a sanitized resolvability error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("PowerShell Gallery", "Pester", "pagination")
          expect(error.full_message).not_to include(secret, "access_token")
          expect(error.cause).to be_nil
        end
      end
    end

    context "when a next-page link contains a secret-bearing invalid URI component" do
      let(:secret) { "GALLERY_COMPONENT_SECRET" }

      before do
        body = feed_xml(
          entries: [entry_xml(version: "5.4.0")],
          next_link: "mailto:#{secret}"
        )
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "raises a sanitized resolvability error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("PowerShell Gallery", "Pester", "pagination")
          expect(error.full_message).not_to include(secret)
          expect(error.cause).to be_nil
        end
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

      it "raises a registry error with the HTTP status" do
        expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(500)
          expect(error.message).to include("PowerShell Gallery", "Pester")
        end
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

      it "raises instead of returning the first page's incomplete release set" do
        expect { fetcher.fetch }.to raise_error(Dependabot::RegistryError) do |error|
          expect(error.status).to eq(500)
        end
      end
    end

    context "when the registry times out" do
      before do
        stub_request(:get, find_packages_by_id_url).to_raise(Excon::Error::Timeout)
      end

      it "raises a typed timeout error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.source).to eq("https://www.powershellgallery.com/api/v2")
        end
      end
    end

    context "when the registry certificate cannot be verified" do
      before do
        stub_request(:get, find_packages_by_id_url)
          .to_raise(Excon::Error::Certificate.new(StandardError.new("certificate failure")))
      end

      it "raises a typed certificate error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceCertificateFailure) do |error|
          expect(error.source).to eq("https://www.powershellgallery.com/api/v2")
          expect(error.cause).to be_nil
        end
      end
    end

    context "when the registry connection breaks" do
      before do
        stub_request(:get, find_packages_by_id_url)
          .to_raise(Excon::Error::Socket.new(EOFError.new))
      end

      it "raises a typed bad-response error" do
        expect { fetcher.fetch }.to raise_error(Dependabot::PrivateSourceBadResponse) do |error|
          expect(error.source).to eq("https://www.powershellgallery.com/api/v2")
        end
      end
    end
  end
end
