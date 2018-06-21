# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_fetchers/dotnet/nuget/sln_project_paths_finder"

RSpec.describe Dependabot::FileFetchers::Dotnet::Nuget::SlnProjectPathsFinder do
  let(:finder) { described_class.new(sln_file: sln_file) }

  let(:sln_file) do
    Dependabot::DependencyFile.new(content: csproj_body, name: sln_file_name)
  end
  let(:sln_file_name) { "GraphQL.Client.sln" }
  let(:csproj_body) { fixture("dotnet", "sln_files", fixture_name) }

  describe "#project_paths" do
    subject(:project_paths) { finder.project_paths }

    let(:fixture_name) { "GraphQL.Client.sln" }
    it "gets the correct paths" do
      expect(project_paths).
        to match_array(
          %w(
            src/GraphQL.Common/GraphQL.Common.csproj
            src/GraphQL.Client/GraphQL.Client.csproj
            tests/GraphQL.Client.Tests/GraphQL.Client.Tests.csproj
            tests/GraphQL.Common.Tests/GraphQL.Common.Tests.csproj
            samples/GraphQL.Client.Sample/GraphQL.Client.Sample.csproj
          )
        )
    end

    context "when this project is already in a nested directory" do
      let(:sln_file_name) { "nested/GraphQL.Client.sln" }

      it "gets the correct paths" do
        expect(project_paths).
          to match_array(
            %w(
              nested/src/GraphQL.Common/GraphQL.Common.csproj
              nested/src/GraphQL.Client/GraphQL.Client.csproj
              nested/tests/GraphQL.Client.Tests/GraphQL.Client.Tests.csproj
              nested/tests/GraphQL.Common.Tests/GraphQL.Common.Tests.csproj
              nested/samples/GraphQL.Client.Sample/GraphQL.Client.Sample.csproj
            )
          )
      end
    end
  end
end
