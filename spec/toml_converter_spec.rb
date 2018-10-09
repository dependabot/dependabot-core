# frozen_string_literal: true

require "spec_helper"
require "toml_converter"

describe TomlConverter do
  describe ".convert_pipenv_outline_tables" do
    subject(:updated_content) do
      described_class.convert_pipenv_outline_tables(content)
    end

    context "without any outline tables" do
      let(:content) { fixture("python", "pipfiles", "exact_version") }
      it { is_expected.to eq(content) }
    end

    context "without an outline table in the middle of the file" do
      let(:content) do
        <<~HEREDOC
          [[source]]
          name = "pypi"
          url = "https://pypi.python.org/simple/"
          verify_ssl = true

          [packages]
          flask = "==1.0.1"

          [packages.raven]
          extras = ["flask"]
          version = ">= 5.27.1, <= 7.0.0"

          [requires]
          python_version = "2.7"
        HEREDOC
      end

      it "converts the outline table to an inline table" do
        expect(updated_content).to eq(
          <<~HEREDOC
            [[source]]
            name = "pypi"
            url = "https://pypi.python.org/simple/"
            verify_ssl = true

            [packages]
            raven = {extras = ["flask"], version = ">= 5.27.1, <= 7.0.0"}
            flask = "==1.0.1"

            [requires]
            python_version = "2.7"
          HEREDOC
        )
      end
    end

    context "without an outline table at the end of the file" do
      let(:content) do
        <<~HEREDOC
          [[source]]
          name = "pypi"
          url = "https://pypi.python.org/simple/"
          verify_ssl = true

          [packages]
          flask = "==1.0.1"

          [requires]
          python_version = "2.7"

          [packages.raven]
          extras = ["flask"]
          version = ">= 5.27.1, <= 7.0.0"
        HEREDOC
      end

      it "converts the outline table to an inline table" do
        expect(updated_content).to eq(
          <<~HEREDOC
            [[source]]
            name = "pypi"
            url = "https://pypi.python.org/simple/"
            verify_ssl = true

            [packages]
            raven = {extras = ["flask"], version = ">= 5.27.1, <= 7.0.0"}
            flask = "==1.0.1"

            [requires]
            python_version = "2.7"

          HEREDOC
        )
      end
    end

    context "without an outline table for a dev-package" do
      let(:content) do
        <<~HEREDOC
          [[source]]
          name = "pypi"
          url = "https://pypi.python.org/simple/"
          verify_ssl = true

          [packages]
          flask = "==1.0.1"

          [dev-packages.raven]
          extras = ["flask"]
          version = ">= 5.27.1, <= 7.0.0"

          [requires]
          python_version = "2.7"
        HEREDOC
      end

      it "converts the outline table to an inline table" do
        expect(updated_content).to eq(
          <<~HEREDOC
            [[source]]
            name = "pypi"
            url = "https://pypi.python.org/simple/"
            verify_ssl = true

            [packages]
            flask = "==1.0.1"

            [requires]
            python_version = "2.7"


            [dev-packages]
            raven = {extras = ["flask"], version = ">= 5.27.1, <= 7.0.0"}
          HEREDOC
        )
      end
    end
  end
end
