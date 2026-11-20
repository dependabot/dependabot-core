# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders/base/package_tag_matcher"

RSpec.describe Dependabot::MetadataFinders::Base::PackageTagMatcher do
  describe ".starts_with_dependency?" do
    it "matches the name followed by a version, with any common separator" do
      expect(described_class.starts_with_dependency?("@cldmv/slothlet@3.24.0", "@cldmv/slothlet")).to be(true)
      expect(described_class.starts_with_dependency?("business-1.8.0", "business")).to be(true)
      expect(described_class.starts_with_dependency?("Flurl.Http.2.4.0", "Flurl.Http")).to be(true)
      expect(described_class.starts_with_dependency?("flurl.http.2.4.0", "Flurl.Http")).to be(true)
    end

    it "does not match another package whose name starts with the dependency's name" do
      expect(described_class.starts_with_dependency?("@cldmv/slothlet-types@3.24.0", "@cldmv/slothlet")).to be(false)
      expect(described_class.starts_with_dependency?("@cldmv/slothlet-i18n@3.24.0", "@cldmv/slothlet")).to be(false)
      expect(described_class.starts_with_dependency?("Flurl.2.8.0", "Flurl.Http")).to be(false)
    end
  end

  describe ".contains_dependency?" do
    it "matches the name followed by a version anywhere in the tag" do
      expect(described_class.contains_dependency?("@pollyjs/ember@0.2.0", "@pollyjs/ember")).to be(true)
      expect(described_class.contains_dependency?("release/business-1.4", "business")).to be(true)
    end

    it "does not match another package whose name starts with the dependency's name" do
      expect(described_class.contains_dependency?("@pollyjs/ember-cli@0.2.0", "@pollyjs/ember")).to be(false)
    end
  end

  describe ".other_package_tag?" do
    it "is true for another package's <package>@<version> tag" do
      expect(described_class.other_package_tag?("@cldmv/slothlet-types@3.24.0", "@cldmv/slothlet")).to be(true)
      expect(described_class.other_package_tag?("eslint-plugin-react-hooks@5.0.0", "React")).to be(true)
    end

    it "is false for the dependency's own tags and for tags without a package name" do
      expect(described_class.other_package_tag?("@cldmv/slothlet@3.24.0", "@cldmv/slothlet")).to be(false)
      expect(described_class.other_package_tag?("v3.24.0", "@cldmv/slothlet")).to be(false)
      expect(described_class.other_package_tag?("business-1.8.0", "business")).to be(false)
    end
  end

  describe ".exact_version_tag?" do
    it "is true only when the tag ends with the whole version" do
      expect(described_class.exact_version_tag?("v3.24.0", "3.24.0")).to be(true)
      expect(described_class.exact_version_tag?("3.24.0", "3.24.0")).to be(true)
      expect(described_class.exact_version_tag?("v3.24", "3.24.0")).to be(false)
      expect(described_class.exact_version_tag?("v13.24.0", "3.24.0")).to be(false)
    end
  end

  describe ".preferred_tag" do
    it "prefers a tag naming the dependency, then the exact version, regardless of order" do
      tags = %w(@cldmv/slothlet-types@3.24.0 v3.24 v3.24.0 @cldmv/slothlet@3.24.0)

      expect([tags, tags.reverse].map { |t| described_class.preferred_tag(t, "@cldmv/slothlet", "3.24.0") }.uniq)
        .to eq(["@cldmv/slothlet@3.24.0"])
    end

    it "keeps other packages' tags when they are the only ones" do
      expect(described_class.preferred_tag(%w(release@1.2.0), "business", "1.2.0")).to eq("release@1.2.0")
    end
  end
end
