# typed: false
# frozen_string_literal: true

RSpec.shared_examples "a pip resolver reading pyproject constraints" do
  let(:dependency_files) { [requirements_file, pyproject, python_version_file] }
  let(:requirements_file) { Dependabot::DependencyFile.new(name: "constraints.txt", content: "django==1.2.4\n") }
  let(:dependency_requirements) do
    [{ file: "constraints.txt", requirement: "==1.2.4", groups: [], source: nil }]
  end
  let(:pyproject) { Dependabot::DependencyFile.new(name: "pyproject.toml", content: pyproject_content) }
  let(:pyproject_content) do
    <<~TOML
      [project]
      dependencies = [
        "requests[security]==2.31.0; python_version >= '3.10'",
        "django==1.2.4",
        false,
        123,
      ]
      [tool.pip]
      constraints = ["constraints.txt", false, 123]
    TOML
  end
  let(:security_advisories) do
    [
      Dependabot::SecurityAdvisory.new(
        dependency_name: dependency_name,
        package_manager: dependency.package_manager,
        vulnerable_versions: ["<= 2.1.0"]
      )
    ]
  end

  before do
    language_manager = instance_double(Dependabot::Python::LanguageVersionManager, python_version: "3.11.0")
    allow(Dependabot::Python::LanguageVersionManager).to receive(:new).and_return(language_manager)
    registry_finder = instance_double(
      Dependabot::Python::Package::PackageRegistryFinder, registry_urls: ["https://pypi.org/simple/"]
    )
    allow(Dependabot::Python::Package::PackageRegistryFinder).to receive(:new).and_return(registry_finder)
    stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
      .to_return(status: 200, body: { info: { requires_dist: ["django (<2)"] } }.to_json)
  end

  it "uses string dependency and constraint entries to block incompatible updates" do
    expect(resolver.latest_resolvable_version).to be_nil
    expect(resolver.lowest_resolvable_security_fix_version).to be_nil
  end

  it "reuses the parsed document between public resolver calls" do
    expect(resolver.latest_resolvable_version).to be_nil
    pyproject.content = "[project]\ndependencies = []\n"
    expect(resolver.lowest_resolvable_security_fix_version).to be_nil
  end

  context "with a scalar constraint path" do
    let(:pyproject_content) { super().sub('["constraints.txt", false, 123]', '"constraints.txt"') }

    it "retains the same compatibility guard" do
      expect(resolver.latest_resolvable_version).to be_nil
    end
  end

  context "with an excluded Python marker" do
    let(:pyproject_content) { super().sub("python_version >= '3.10'", "python_version < '3.0'") }

    it "does not use the excluded pin" do
      expect(resolver.latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
    end
  end

  ["project = false", "[project]\ndependencies = false"].each do |content|
    context "with a malformed project container #{content.inspect}" do
      let(:pyproject_content) { content }

      it "retains the empty dependency fallback" do
        expect(resolver.latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
      end
    end
  end

  {
    "missing content" => nil,
    "invalid TOML" => "[invalid",
    "duplicate keys" => "[project]\ndependencies = []\ndependencies = []"
  }.each do |description, content|
    context "with #{description}" do
      let(:pyproject_content) { content }

      it "caches the existing empty-document fallback" do
        expect(resolver.latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        pyproject.content = "[project]\ndependencies = [\"requests==2.31.0\"]\n"
        expect(resolver.lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.1.1"))
      end
    end
  end
end
