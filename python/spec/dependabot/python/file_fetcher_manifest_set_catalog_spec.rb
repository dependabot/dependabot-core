# typed: true
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/manifest_sets"
require "dependabot/python/file_fetcher"
require "dependabot/python/dependency_grapher/requirements_layers"

# Keeps the static manifest-set catalog's pypi rules in step with the names the Python fetcher and
# requirements grapher actually treat as manifests. uv.lock is checked in the uv gem's spec.
RSpec.describe Dependabot::Python::FileFetcher do
  describe "manifest-set catalog rules" do
    let(:ecosystem) { Dependabot::ManifestSets.catalog.ecosystem("pypi") }
    let(:uv_selectors) { %w(uv.lock) }

    let(:basenames) do
      fixtures = JSON.parse(File.read(File.join(Dependabot::ManifestSets::FIXTURES_DIR, "filenames.json")))
      fixture_names = fixtures["cases"].select { |c| c["ecosystem"] == "pypi" && !c.key?("catalog") }
                                       .map { |c| c["basename"] }
      extra_names = %w(
        requirements.txt Requirements.txt REQUIREMENTS.txt requirements.TXT requirements.txt.bak
        prequire.txt acquire.txt codependent.txt require.dev.txt require-dev.txt py3-depends.txt
        dependency.txt x.dependencies-prod.txt README.txt notes.txt constraints.in requirements.in
        setup.py Setup.py setup.cfg pyproject.toml Pipfile Pipfile.lock poetry.lock pdm.lock .python-version
      ) + ["dev requirements.txt", "requirements dev.txt"]
      (fixture_names + extra_names).uniq - uv_selectors
    end

    # The grapher's case-insensitive name filters also fold U+017F LONG S to "s"; catalog rules are
    # ASCII-only by design, so these names are deliberately outside the catalog.
    let(:unicode_folding_divergences) { ["requirementſ.txt", "REQUIREMENTſ.txt", "dependencieſ.txt", "dependſ.txt"] }

    # The fetcher keeps any .txt/.in file whose content parses; the grapher then keeps only .txt files
    # whose names look like manifests. The fetcher's extension and exact-name checks are case-sensitive.
    def core_manifest?(name)
      layers = Dependabot::Python::DependencyGrapher::RequirementsLayers
      return layers.manifest_txt_filename?(name) if name.end_with?(".txt")
      return true if name.end_with?(".in")

      ["pyproject.toml", *Dependabot::Python::FileFetcher::ECOSYSTEM_SPECIFIC_FILES].include?(name)
    end

    it "matches exactly the basenames core treats as pip manifests" do
      mismatches = basenames.reject { |name| ecosystem.rule_matches?(name) == core_manifest?(name) }
      expect(mismatches).to match_array(unicode_folding_divergences)
    end

    it "only diverges from core on non-ASCII names that core's case folding accepts" do
      expect(unicode_folding_divergences.map { |name| [ecosystem.rule_matches?(name), core_manifest?(name)] })
        .to all(eq([false, true]))
    end

    it "only matches basenames that satisfy the fetcher's required files check" do
      matched = basenames.select { |name| ecosystem.rule_matches?(name) }
      expect(matched.reject { |name| described_class.required_files_in?([name]) }).to eq([])
    end

    it "selects pip as the owner whenever no uv selector is present" do
      expect(ecosystem.select_owner(%w(requirements.txt pyproject.toml)).owner&.id).to eq("pip")
    end
  end
end
