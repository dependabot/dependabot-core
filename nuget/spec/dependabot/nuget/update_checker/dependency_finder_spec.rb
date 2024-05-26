# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/dependency_finder"

RSpec.describe Dependabot::Nuget::UpdateChecker::DependencyFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: "test/repo"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end

  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "1.1.1", groups: ["dependencies"], source: nil }]
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "1.1.1" }

  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("csproj", "basic.csproj") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  # Can get transitive dependencies
  describe "#transitive_dependencies", :vcr do
    subject(:transitive_dependencies) { finder.transitive_dependencies }

    its(:length) { is_expected.to eq(34) }
  end

  context "api.nuget.org is not hit if it's not in the NuGet.Config" do
    let(:dependency_version) { "42.42.42" }
    let(:nuget_config_body) { fixture("configs", "example.com_nuget.config") }
    let(:nuget_config) { Dependabot::DependencyFile.new(name: "NuGet.Config", content: nuget_config_body) }
    let(:dependency_files) { [csproj, nuget_config] }

    subject(:transitive_dependencies) { finder.transitive_dependencies }

    def create_nupkg(nuspec_name, nuspec_fixture_path)
      content = Zip::OutputStream.write_buffer do |zio|
        zio.put_next_entry("#{nuspec_name}.nuspec")
        zio.write(fixture("nuspecs", nuspec_fixture_path))
      end
      content.rewind
      content.sysread
    end

    before(:context) do
      disallowed_urls = %w(
        https://api.nuget.org/v3/index.json
        https://api.nuget.org/v3-flatcontainer/microsoft.extensions.dependencymodel/42.42.42/microsoft.extensions.dependencymodel.nuspec
        https://api.nuget.org/v3-flatcontainer/microsoft.netcore.platforms/43.43.43/microsoft.netcore.platforms.nuspec
      )

      disallowed_urls.each do |url|
        stub_request(:get, url)
          .to_raise(StandardError.new("Not allowed to query `#{url}`"))
      end

      stub_request(:get, "https://nuget.example.com/v3/index.json")
        .to_return(status: 200, body: fixture("nuget_responses", "example_index.json"))
      stub_request(:get, "https://api.example.com/v3-flatcontainer/microsoft.extensions.dependencymodel/42.42.42/microsoft.extensions.dependencymodel.42.42.42.nupkg")
        .to_return(status: 200, body: create_nupkg("Microsoft.Extensions.DependencyModel",
                                                   "Microsoft.Extensions.DependencyModel_42.42.42_faked.nuspec"))
      stub_request(:get, "https://api.example.com/v3-flatcontainer/microsoft.netcore.platforms/43.43.43/microsoft.netcore.platforms.43.43.43.nupkg")
        .to_return(status: 200, body: create_nupkg("Microsoft.NETCore.Platforms",
                                                   "Microsoft.NETCore.Platforms_43.43.43_faked.nuspec"))
    end

    # this test doesn't really care about the dependency count, we just need to ensure that `api.nuget.org` wasn't hit
    its(:length) do
      is_expected.to eq(1)
    end
  end
end
