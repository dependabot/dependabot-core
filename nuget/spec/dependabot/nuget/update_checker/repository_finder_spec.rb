# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/repository_finder"
require_relative "../nuget_search_stubs"

RSpec.describe Dependabot::Nuget::RepositoryFinder do
  RSpec.configure do |config|
    config.include(NuGetSearchStubs)
  end

  subject(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      config_files: [config_file].compact
    )
  end

  let(:config_file) { nil }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Microsoft.Extensions.DependencyModel",
      version: "1.1.1",
      requirements: [{
        requirement: "1.1.1",
        file: "my.csproj",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "nuget"
    )
  end

  describe "local path in NuGet.Config" do
    subject(:known_repositories) { finder.known_repositories }

    let(:config_file) do
      nuget_config_content = <<~XML
        <configuration>
          <packageSources>
            <clear />
            <add key="LocalSource1" value="SomePath" />
            <add key="LocalSource2" value="./RelativePath" />
            <add key="LocalSource3" value="/AbsolutePath" />
            <add key="PublicSource" value="https://nuget.example.com/index.json" />
          </packageSources>
        </configuration>
      XML
      Dependabot::DependencyFile.new(
        name: "NuGet.Config",
        content: nuget_config_content,
        directory: "some/directory"
      )
    end

    it "finds all local paths" do
      urls = known_repositories.map { |r| r[:url] }
      expected = [
        "/some/directory/SomePath",
        "/some/directory/RelativePath",
        "/AbsolutePath",
        "https://nuget.example.com/index.json"
      ]
      expect(urls).to match_array(expected)
    end
  end

  describe "environment variables in NuGet.Config" do
    subject(:known_repositories) { finder.known_repositories }

    let(:config_file) do
      nuget_config_content = <<~XML
        <configuration>
          <packageSources>
            <clear />
            <add key="SomePackageSource" value="%FEED_URL%" />
          </packageSources>
          <packageSourceCredentials>
            <SomePackageSource>
              <add key="Username" value="user" />
              <add key="ClearTextPassword" value="(head)%THIS_VARIBLE_EXISTS%(mid)%THIS_VARIABLE_DOES_NOT%(tail)" />
            </SomePackageSource>
          </packageSourceCredentials>
        </configuration>
      XML
      Dependabot::DependencyFile.new(
        name: "NuGet.Config",
        content: nuget_config_content
      )
    end

    context "are expanded" do
      before do
        allow(Dependabot.logger).to receive(:warn)
        ENV["FEED_URL"] = "https://nuget.example.com/index.json"
        ENV["THIS_VARIBLE_EXISTS"] = "replacement-text"
        ENV.delete("THIS_VARIABLE_DOES_NOT")
      end

      it "contains the expected values and warns on unavailable" do
        repo = known_repositories[0]
        expect(repo[:url]).to eq("https://nuget.example.com/index.json")
        expect(repo[:token]).to eq("user:(head)replacement-text(mid)%THIS_VARIABLE_DOES_NOT%(tail)")
        expect(Dependabot.logger).to have_received(:warn).with(
          <<~WARN
            The variable '%THIS_VARIABLE_DOES_NOT%' could not be expanded in NuGet.Config
          WARN
        )
      end

      after do
        ENV.delete("THIS_VARIBLE_EXISTS")
        ENV.delete("THIS_VARIABLE_DOES_NOT")
      end
    end
  end

  describe "dependency_urls" do
    subject(:dependency_urls) { finder.dependency_urls }

    it "gets the right URL without making any requests" do
      expect(dependency_urls).to eq(
        [{
          base_url: "https://api.nuget.org/v3-flatcontainer/",
          registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/" \
                            "microsoft.extensions.dependencymodel/index.json",
          repository_url: "https://api.nuget.org/v3/index.json",
          versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                        "microsoft.extensions.dependencymodel/index.json",
          search_url: "https://azuresearch-usnc.nuget.org/query" \
                      "?q=microsoft.extensions.dependencymodel" \
                      "&prerelease=true&semVerLevel=2.0.0",
          auth_header: {},
          repository_type: "v3"
        }]
      )
    end

    context "with a URL passed as a credential" do
      let(:custom_repo_url) do
        "https://www.myget.org/F/exceptionless/api/v3/index.json"
      end
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "nuget_feed",
          "url" => custom_repo_url,
          "token" => "my:passw0rd"
        }]
      end

      before do
        stub_request(:get, custom_repo_url)
          .with(basic_auth: %w(my passw0rd))
          .to_return(
            status: 200,
            body: fixture("nuget_responses", "myget_base.json")
          )
      end

      it "gets the right URL" do
        expect(dependency_urls).to eq(
          [{
            base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
            registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                              "microsoft.extensions.dependencymodel/index.json",
            repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "index.json",
            versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "flatcontainer/microsoft.extensions." \
                          "dependencymodel/index.json",
            search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                        "query?q=microsoft.extensions.dependencymodel" \
                        "&prerelease=true&semVerLevel=2.0.0",
            auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
            repository_type: "v3"
          }]
        )
      end

      context "that does not return PackageBaseAddress" do
        let(:custom_repo_url) { "http://localhost:8082/artifactory/api/nuget/v3/nuget-local" }

        before do
          stub_request(:get, custom_repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "artifactory_base.json")
            )
        end

        it "gets the right URL" do
          expect(dependency_urls).to eq(
            [{
              base_url: nil,
              registration_url: "http://localhost:8081/artifactory/api/nuget/v3/" \
                                "dependabot-nuget-local/registration/microsoft.extensions.dependencymodel/index.json",
              repository_url: custom_repo_url,
              search_url: "http://localhost:8081/artifactory/api/nuget/v3/" \
                          "dependabot-nuget-local/query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
              repository_type: "v3"
            }]
          )
        end
      end

      context "that has URLs that need to be escaped" do
        let(:custom_repo_url) { "https://www.myget.org/F/exceptionless/api with spaces/v3/index.json" }

        before do
          stub_request(:get, "https://www.myget.org/F/exceptionless/api%20with%20spaces/v3/index.json")
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URL" do
          expect(dependency_urls).to eq(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api%20with%20spaces/v3/index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
              repository_type: "v3"
            }]
          )
        end
      end

      context "that 404s" do
        before { stub_request(:get, custom_repo_url).to_return(status: 404) }

        # TODO: Might want to raise here instead?
        it { is_expected.to eq([]) }
      end

      context "that 403s" do
        before { stub_request(:get, custom_repo_url).to_return(status: 403) }

        it "raises a useful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { finder.dependency_urls }
            .to raise_error do |error|
              expect(error).to be_a(error_class)
              expect(error.source).to eq(custom_repo_url)
            end
        end
      end

      context "without a token" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "nuget_feed",
            "url" => custom_repo_url
          }]
        end

        before do
          stub_request(:get, custom_repo_url)
            .with(basic_auth: nil)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URL" do
          expect(dependency_urls).to eq(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end
    end

    context "with a URL included in the nuget.config" do
      let(:config_file) do
        Dependabot::DependencyFile.new(
          name: "NuGet.Config",
          content: fixture("configs", config_file_fixture_name)
        )
      end
      let(:config_file_fixture_name) { "nuget.config" }

      before do
        repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
        stub_request(:get, repo_url).to_return(status: 404)
        stub_request(:get, repo_url)
          .with(basic_auth: %w(my passw0rd))
          .to_return(
            status: 200,
            body: fixture("nuget_responses", "myget_base.json")
          )
      end

      # skipped
      # it "gets the right URLs" do
      #   expect(dependency_urls).to match_array(
      #     [{
      #       repository_url: "https://api.nuget.org/v3/index.json",
      #       versions_url: "https://api.nuget.org/v3-flatcontainer/" \
      #                     "microsoft.extensions.dependencymodel/index.json",
      #       search_url: "https://azuresearch-usnc.nuget.org/query" \
      #                   "?q=microsoft.extensions.dependencymodel" \
      #                   "&prerelease=true&semVerLevel=2.0.0",
      #       auth_header: {},
      #       repository_type: "v3"
      #     }, {
      #       repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
      #                       "index.json",
      #       versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
      #                     "flatcontainer/microsoft.extensions." \
      #                     "dependencymodel/index.json",
      #       search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
      #                   "query?q=microsoft.extensions.dependencymodel" \
      #                   "&prerelease=true&semVerLevel=2.0.0",
      #       auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
      #       repository_type: "v3"
      #     }]
      #   )
      # end

      context "include the default repository" do
        let(:config_file_fixture_name) { "include_default_disable_ext_sources.config" }

        it "with disable external source" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                                "registration1/microsoft.extensions.dependencymodel/index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
              repository_type: "v3"
            }, {
              base_url: "https://api.nuget.org/v3-flatcontainer/",
              registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://api.nuget.org/v3/index.json",
              versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                            "microsoft.extensions.dependencymodel/index.json",
              search_url: "https://azuresearch-usnc.nuget.org/query" \
                          "?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "that overrides the default package sources" do
        let(:config_file_fixture_name) { "override_def_source_with_same_key.config" }

        before do
          repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "when the default api key of default registry is provided without clear" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end

        let(:config_file_fixture_name) { "override_def_source_with_same_key_default.config" }

        it "when the default api key of default registry is provided with clear" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "that doesn't include the default repository" do
        let(:config_file_fixture_name) { "excludes_default.config" }

        it "still includes the default repository (as it wasn't cleared)" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://api.nuget.org/v3-flatcontainer/",
              registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://api.nuget.org/v3/index.json",
              versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                            "microsoft.extensions.dependencymodel/index.json",
              search_url: "https://azuresearch-usnc.nuget.org/query" \
                          "?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }, {
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
              repository_type: "v3"
            }]
          )
        end

        context "and clears it" do
          let(:config_file_fixture_name) { "clears_default.config" }

          it "still excludes the default repository" do
            expect(dependency_urls).to match_array(
              [{
                base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
                registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                  "microsoft.extensions.dependencymodel/index.json",
                repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                                "index.json",
                versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "flatcontainer/microsoft.extensions." \
                              "dependencymodel/index.json",
                search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "query?q=microsoft.extensions.dependencymodel" \
                            "&prerelease=true&semVerLevel=2.0.0",
                auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
                repository_type: "v3"
              }]
            )
          end
        end

        context "that has disabled package sources" do
          let(:config_file_fixture_name) { "disabled_sources.config" }

          it "only includes the enabled package sources" do
            expect(dependency_urls).to match_array(
              [{
                base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
                registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                  "microsoft.extensions.dependencymodel/index.json",
                repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                                "index.json",
                versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "flatcontainer/microsoft.extensions." \
                              "dependencymodel/index.json",
                search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "query?q=microsoft.extensions.dependencymodel" \
                            "&prerelease=true&semVerLevel=2.0.0",
                auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
                repository_type: "v3"
              }]
            )
          end
        end

        context "that has disabled default package sources" do
          let(:config_file_fixture_name) { "disabled_default_sources.config" }

          it "only includes the enable package sources" do
            expect(dependency_urls).to match_array(
              [{
                base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
                registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                  "microsoft.extensions.dependencymodel/index.json",
                repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                                "index.json",
                versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "flatcontainer/microsoft.extensions." \
                              "dependencymodel/index.json",
                search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "query?q=microsoft.extensions.dependencymodel" \
                            "&prerelease=true&semVerLevel=2.0.0",
                auth_header: { "Authorization" => "Basic bXk6cGFzc3cwcmQ=" },
                repository_type: "v3"
              }]
            )
          end
        end
      end

      context "that has a numeric key" do
        let(:config_file_fixture_name) { "numeric_key.config" }

        before do
          repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "that only provides versioned `SearchQueryService`` entries" do
        let(:config_file_fixture_name) { "versioned_search.config" }

        before do
          repo_url = "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-libraries/nuget/v3/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "index.json", "versioned_SearchQueryService.index.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/flat2/",
              registration_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/registrations2/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-libraries/nuget/v3/index.json",
              versions_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/flat2/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/query2/?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "includes repositories in the `trustedSigners` section" do
        let(:config_file_fixture_name) { "with_trustedSigners.config" }

        before do
          repo_url = "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-libraries/nuget/v3/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "index.json", "versioned_SearchQueryService.index.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to eq(
            [{
              base_url: "https://api.nuget.org/v3-flatcontainer/",
              registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://api.nuget.org/v3/index.json",
              versions_url: "https://api.nuget.org/v3-flatcontainer/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://azuresearch-usnc.nuget.org/query?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            },
             {
               base_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/flat2/",
               registration_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/registrations2/microsoft.extensions.dependencymodel/index.json",
               repository_url: "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-libraries/nuget/v3/index.json",
               versions_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/flat2/microsoft.extensions.dependencymodel/index.json",
               search_url: "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/516521bf-6417-457e-9a9c-0a4bdfde03e7/nuget/v3/query2/?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
               auth_header: {},
               repository_type: "v3"
             }]
          )
        end
      end

      context "with GitHub packages url" do
        let(:config_file_fixture_name) { "github.nuget.config" }

        before do
          repo_url = "https://nuget.pkg.github.com/some-namespace/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "index.json", "github.index.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to eq(
            [{
              base_url: "https://nuget.pkg.github.com/some-namespace/download",
              registration_url: "https://nuget.pkg.github.com/some-namespace/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://nuget.pkg.github.com/some-namespace/index.json",
              versions_url: "https://nuget.pkg.github.com/some-namespace/download/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://nuget.pkg.github.com/some-namespace/query?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "that has a non-ascii key" do
        let(:config_file_fixture_name) { "non_ascii_key.config" }

        before do
          repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
          stub_request(:get, repo_url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                              "index.json",
              versions_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                            "flatcontainer/microsoft.extensions." \
                            "dependencymodel/index.json",
              search_url: "https://www.myget.org/F/exceptionless/api/v3/" \
                          "query?q=microsoft.extensions.dependencymodel" \
                          "&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "that uses the v2 API alongside the v3 API" do
        let(:config_file_fixture_name) { "with_v2_endpoints.config" }

        before do
          v2_repo_urls = %w(
            https://www.nuget.org/api/v2/
            https://www.myget.org/F/azure-appservice/api/v2
            https://www.myget.org/F/azure-appservice-staging/api/v2
            https://www.myget.org/F/fusemandistfeed/api/v2
            https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/
          )

          v2_repo_urls.each do |repo_url|
            stub_request(:get, repo_url)
              .to_return(
                status: 200,
                body: fixture("nuget_responses", "v2_base.xml")
              )
          end

          url = "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json"
          stub_request(:get, url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url:
                "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json",
              versions_url:
                "https://www.myget.org/F/exceptionless/api/v3/" \
                "flatcontainer/microsoft.extensions.dependencymodel/index.json",
              search_url:
                "https://www.myget.org/F/exceptionless/api/v3/" \
                "query?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }, {
              base_url: "https://www.nuget.org/api/v2",
              repository_url: "https://www.nuget.org/api/v2",
              versions_url:
                "https://www.nuget.org/api/v2/FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }]
          )
        end
      end

      context "that has no base url in v2 API response" do
        let(:config_file_fixture_name) { "with_v2_endpoints.config" }

        before do
          v2_repo_urls = %w(
            https://www.nuget.org/api/v2/
            https://www.myget.org/F/azure-appservice/api/v2
            https://www.myget.org/F/azure-appservice-staging/api/v2
            https://www.myget.org/F/fusemandistfeed/api/v2
            https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/
          )

          v2_repo_urls.each do |repo_url|
            stub_request(:get, repo_url)
              .to_return(
                status: 200,
                body: fixture("nuget_responses", "v2_no_base.xml")
              )
          end

          url = "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json"
          stub_request(:get, url)
            .to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )
        end

        it "gets the right URLs" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/",
              registration_url: "https://www.myget.org/F/exceptionless/api/v3/registration1/" \
                                "microsoft.extensions.dependencymodel/index.json",
              repository_url:
                "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json",
              versions_url:
                "https://www.myget.org/F/exceptionless/api/v3/" \
                "flatcontainer/microsoft.extensions.dependencymodel/index.json",
              search_url:
                "https://www.myget.org/F/exceptionless/api/v3/" \
                "query?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }, {
              base_url: "https://www.nuget.org/api/v2/",
              repository_url: "https://www.nuget.org/api/v2/",
              versions_url:
                "https://www.nuget.org/api/v2/FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }, {
              base_url: "https://www.myget.org/F/azure-appservice/api/v2",
              repository_url: "https://www.myget.org/F/azure-appservice/api/v2",
              versions_url:
                "https://www.myget.org/F/azure-appservice/api/v2/" \
                "FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }, {
              base_url: "https://www.myget.org/F/azure-appservice-staging/api/v2",
              repository_url:
                "https://www.myget.org/F/azure-appservice-staging/api/v2",
              versions_url:
                "https://www.myget.org/F/azure-appservice-staging/api/v2/" \
                "FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }, {
              base_url: "https://www.myget.org/F/fusemandistfeed/api/v2",
              repository_url: "https://www.myget.org/F/fusemandistfeed/api/v2",
              versions_url:
                "https://www.myget.org/F/fusemandistfeed/api/v2/" \
                "FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }, {
              base_url: "https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/",
              repository_url:
                "https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/",
              versions_url:
                "https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/" \
                "FindPackagesById()?id=" \
                "'Microsoft.Extensions.DependencyModel'",
              auth_header: {},
              repository_type: "v2"
            }]
          )
        end
      end

      context "matching `packageSourceMapping` entries are honored" do
        let(:config_file) do
          nuget_config_content = <<~XML
            <configuration>
              <packageSources>
                <clear />
                <add key="source1" value="https://nuget.example.com/source1/index.json" />
                <add key="source2" value="https://nuget.example.com/source2/index.json" />
                <add key="source3" value="https://nuget.example.com/source3/index.json" />
              </packageSources>
              <packageSourceMapping>
                <packageSource key="source1">
                  <package pattern="Microsoft.*" /><!-- less specific, will be skipped -->
                </packageSource>
                <packageSource key="source2">
                  <package pattern="MICROSOFT.EXTENSIONS.*" /><!-- most specific, use this; case insensitive -->
                </packageSource>
                <packageSource key="source3">
                  <package pattern="Some.Other.Package" /><!-- something else entirely -->
                </packageSource>
              </packageSourceMapping>
            </configuration>
          XML
          Dependabot::DependencyFile.new(
            name: "NuGet.Config",
            content: nuget_config_content
          )
        end

        before do
          # `source1` and `source3` should never be queried
          stub_index_json("https://nuget.example.com/source2/index.json")
        end

        it "matches on the best pattern" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://nuget.example.com/source2/PackageBaseAddress",
              registration_url: "https://nuget.example.com/source2/RegistrationsBaseUrl/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://nuget.example.com/source2/index.json",
              versions_url: "https://nuget.example.com/source2/PackageBaseAddress/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://nuget.example.com/source2/SearchQueryService?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end

      context "non-matching `packageSourceMapping` entries are ignored" do
        let(:config_file) do
          nuget_config_content = <<~XML
            <configuration>
              <packageSources>
                <clear />
                <add key="source1" value="https://nuget.example.com/source1/index.json" />
                <add key="source2" value="https://nuget.example.com/source2/index.json" />
                <add key="source3" value="https://nuget.example.com/source3/index.json" />
              </packageSources>
              <packageSourceMapping>
                <packageSource key="source1">
                  <package pattern="Some.Package.*" /><!-- no match -->
                </packageSource>
                <packageSource key="source2">
                  <package pattern="Some.Other.Package.*" /><!-- no match -->
                </packageSource>
                <packageSource key="source3">
                  <package pattern="Still.Some.Other.Package" /><!-- no match -->
                </packageSource>
              </packageSourceMapping>
            </configuration>
          XML
          Dependabot::DependencyFile.new(
            name: "NuGet.Config",
            content: nuget_config_content
          )
        end

        before do
          # all sources will need to be queried
          stub_index_json("https://nuget.example.com/source1/index.json")
          stub_index_json("https://nuget.example.com/source2/index.json")
          stub_index_json("https://nuget.example.com/source3/index.json")
        end

        it "returns all sources" do
          expect(dependency_urls).to match_array(
            [{
              base_url: "https://nuget.example.com/source1/PackageBaseAddress",
              registration_url: "https://nuget.example.com/source1/RegistrationsBaseUrl/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://nuget.example.com/source1/index.json",
              versions_url: "https://nuget.example.com/source1/PackageBaseAddress/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://nuget.example.com/source1/SearchQueryService?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }, {
              base_url: "https://nuget.example.com/source2/PackageBaseAddress",
              registration_url: "https://nuget.example.com/source2/RegistrationsBaseUrl/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://nuget.example.com/source2/index.json",
              versions_url: "https://nuget.example.com/source2/PackageBaseAddress/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://nuget.example.com/source2/SearchQueryService?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }, {
              base_url: "https://nuget.example.com/source3/PackageBaseAddress",
              registration_url: "https://nuget.example.com/source3/RegistrationsBaseUrl/microsoft.extensions.dependencymodel/index.json",
              repository_url: "https://nuget.example.com/source3/index.json",
              versions_url: "https://nuget.example.com/source3/PackageBaseAddress/microsoft.extensions.dependencymodel/index.json",
              search_url: "https://nuget.example.com/source3/SearchQueryService?q=microsoft.extensions.dependencymodel&prerelease=true&semVerLevel=2.0.0",
              auth_header: {},
              repository_type: "v3"
            }]
          )
        end
      end
    end
  end
end
