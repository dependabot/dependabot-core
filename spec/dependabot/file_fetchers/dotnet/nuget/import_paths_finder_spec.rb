# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_fetchers/dotnet/nuget/import_paths_finder"

RSpec.describe Dependabot::FileFetchers::Dotnet::Nuget::ImportPathsFinder do
  let(:finder) { described_class.new(project_file: project_file) }

  let(:project_file) do
    Dependabot::DependencyFile.new(content: csproj_body, name: csproj_name)
  end
  let(:csproj_name) { "my.csproj" }
  let(:csproj_body) { fixture("dotnet", "csproj", fixture_name) }

  describe "#import_paths" do
    subject(:import_paths) { finder.import_paths }

    context "when the file does not include any imports" do
      let(:fixture_name) { "basic.csproj" }
      it { is_expected.to eq([]) }
    end

    context "when the file does include an import" do
      let(:fixture_name) { "import.csproj" }
      it { is_expected.to eq(["commonprops.props"]) }

      context "when this project is already in a nested directory" do
        let(:csproj_name) { "nested/my.csproj" }

        it { is_expected.to eq(["nested/commonprops.props"]) }
      end
    end
  end

  describe "#project_reference_paths" do
    subject(:project_reference_paths) { finder.project_reference_paths }

    context "when the file does not reference any other projects" do
      let(:fixture_name) { "basic.csproj" }
      it { is_expected.to eq([]) }
    end

    context "when the file does reference another project" do
      let(:fixture_name) { "project_reference.csproj" }
      let(:csproj_name) { "nested/my.csproj" }
      it { is_expected.to eq(["ref/another.csproj"]) }
    end
  end
end
