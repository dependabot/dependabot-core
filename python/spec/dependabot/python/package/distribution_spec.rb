# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/package/distribution"

RSpec.describe Dependabot::Python::Package::Distribution do
  let(:version) { "1.2.3" }
  let(:context) { "PyPI registry releases[1.2.3][0]" }
  let(:project_url) { "https://registry.example.test/simple/demo/" }

  describe ".from_pypi" do
    subject(:distribution) { described_class.from_pypi(data, version_string: version, context: context) }

    let(:data) do
      {
        "version" => "ignored",
        "upload_time" => "2024-01-02T03:04:05Z",
        "requires_python" => ">=3.8",
        "python_version" => "py3",
        "yanked" => true,
        "yanked_reason" => "Broken archive",
        "downloads" => 0,
        "url" => "https://example.test/demo.whl",
        "packagetype" => "bdist_wheel"
      }
    end

    it "parses consumed fields and uses the adapter's version" do
      expect(distribution).to have_attributes(
        version_string: "1.2.3",
        released_at: Time.utc(2024, 1, 2, 3, 4, 5),
        requires_python: ">=3.8",
        python_version: "py3",
        yanked: true,
        yanked_reason: "Broken archive",
        downloads: 0,
        url: "https://example.test/demo.whl",
        package_type: "bdist_wheel"
      )
    end

    context "with absent fields" do
      let(:data) { {} }

      it "supplies the existing defaults" do
        expect(distribution).to have_attributes(
          released_at: nil,
          requires_python: nil,
          python_version: nil,
          yanked: false,
          yanked_reason: nil,
          downloads: -1,
          url: nil,
          package_type: nil
        )
      end
    end

    context "with null fields" do
      let(:data) { super().transform_values { nil } }

      it "preserves nullable metadata and defaults" do
        expect(distribution).to have_attributes(released_at: nil, yanked: false, downloads: -1, url: nil)
      end
    end

    context "with empty strings and an ignored newer date field" do
      let(:data) do
        { "url" => "", "requires_python" => "", "python_version" => "", "yanked_reason" => "",
          "packagetype" => "", "upload_time_iso_8601" => "2024-01-02T00:00:00Z" }
      end

      it "does not normalize strings or change timestamp precedence" do
        expect(distribution).to have_attributes(
          url: "",
          requires_python: "",
          python_version: "",
          yanked_reason: "",
          package_type: "",
          released_at: nil
        )
      end
    end

    {
      "upload_time" => false, "requires_python" => [], "python_version" => 123,
      "yanked" => "reason", "yanked_reason" => false, "downloads" => false,
      "url" => {}, "packagetype" => 123
    }.each do |field, value|
      context "with invalid #{field}" do
        let(:data) { super().merge(field => value) }

        it "raises a contextual field error" do
          expect { distribution }.to raise_error(Dependabot::DependencyFileNotResolvable, /#{Regexp.escape(field)}/)
        end
      end
    end

    ["", "do-not-echo-this"].each do |value|
      context "with an invalid timestamp #{value.inspect}" do
        let(:data) { super().merge("upload_time" => value) }

        it "does not retain the raw value or parser exception" do
          expect { distribution }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(context, "upload_time")
            expect(error.message).not_to include("do-not-echo-this")
            expect(error.cause).to be_nil
          end
        end
      end
    end
  end

  describe ".from_simple" do
    subject(:distribution) do
      described_class.from_simple(data, version_string: version, context: context, project_url: project_url)
    end

    let(:data) { { "url" => "../files/demo.whl#sha256=abc", "upload-time" => "2024-01-02T00:00:00Z" } }

    it "resolves file URLs and reads Simple API fields" do
      expect(distribution).to have_attributes(
        url: "https://registry.example.test/simple/files/demo.whl#sha256=abc",
        released_at: Time.utc(2024, 1, 2),
        downloads: -1,
        package_type: nil,
        python_version: nil
      )
    end

    [nil, false, true, "", "Broken wheel"].each do |value|
      context "with yanked #{value.inspect}" do
        let(:data) { super().merge("yanked" => value) }

        it "preserves withdrawal status and reason" do
          expect(distribution.yanked).to eq(!value.nil? && value != false)
          expect(distribution.yanked_reason).to eq(value.is_a?(String) ? value : nil)
        end
      end
    end

    context "with invalid withdrawal metadata" do
      let(:data) { super().merge("yanked" => 1) }

      it "rejects non-boolean, non-string values" do
        expect { distribution }.to raise_error(Dependabot::DependencyFileNotResolvable, /yanked/)
      end
    end

    context "with credentials in the project URL" do
      let(:project_url) { "https://test-user:test-password@registry.example.test/simple/demo/" }

      it "does not expose credentials in the download URL" do
        expect(distribution.url).to eq("https://registry.example.test/simple/files/demo.whl#sha256=abc")
      end
    end

    context "with an invalid file URL" do
      let(:data) { super().merge("url" => "https://do-not-echo-this/invalid path") }

      it "reports the field without the invalid URL" do
        expect { distribution }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include(context, "url")
          expect(error.message).not_to include("do-not-echo-this")
          expect(error.cause).to be_nil
        end
      end
    end
  end

  describe ".from_html" do
    subject(:distribution) do
      node = Nokogiri::HTML(html).at_css("a")
      described_class.from_html(node, version_string: version, context: context, project_url: project_url)
    end

    let(:html) do
      '<a href="../files/demo.whl?signature=keep#sha256=abc" data-requires-python="&gt;=3.8" ' \
        'data-yanked="Broken wheel">demo-1.2.3.whl</a>'
    end

    it "extracts attributes instead of returning markup" do
      expect(distribution).to have_attributes(
        url: "https://registry.example.test/simple/files/demo.whl?signature=keep#sha256=abc",
        requires_python: ">=3.8",
        yanked: true,
        yanked_reason: "Broken wheel",
        released_at: nil
      )
    end

    context "with the withdrawal marker in an unrelated attribute" do
      let(:html) { '<a href="demo.whl" title="data-yanked">demo-1.2.3.whl</a>' }

      it "does not mark the file as withdrawn" do
        expect(distribution).to have_attributes(yanked: false, yanked_reason: nil)
      end
    end

    context "with an empty withdrawal attribute" do
      let(:html) { '<a href="demo.whl" data-yanked="">demo-1.2.3.whl</a>' }

      it "retains the empty reason and marks the file as withdrawn" do
        expect(distribution).to have_attributes(yanked: true, yanked_reason: "")
      end
    end

    context "with a valueless withdrawal attribute" do
      let(:html) { '<a href="demo.whl" data-yanked>demo-1.2.3.whl</a>' }

      it "uses the attribute's presence" do
        expect(distribution.yanked).to be(true)
      end
    end

    context "without a download URL" do
      let(:html) { "<a>demo-1.2.3.whl</a>" }

      it "keeps the URL nullable" do
        expect(distribution.url).to be_nil
      end
    end
  end
end
