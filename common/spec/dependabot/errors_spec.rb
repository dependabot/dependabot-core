# frozen_string_literal: true

require "spec_helper"
require "dependabot/errors"

RSpec.describe Dependabot::DependabotError do
  let(:error) { described_class.new(message) }
  let(:message) do
    "some error"
  end

  describe "#message" do
    subject { error.message }

    it { is_expected.to eq("some error") }

    context "with dependabot temp path" do
      let(:message) do
        "tmp/dependabot_123/path error"
      end

      it { is_expected.to eq("dependabot_tmp_dir/path error") }
    end

    context "with http basic auth" do
      let(:message) do
        "git://user:token@github.com error"
      end

      it { is_expected.to eq("git://<redacted>@github.com error") }
    end

    context "with escaped basic auth uri" do
      let(:message) do
        "git://user:token%40github.com error"
      end

      it { is_expected.to eq("git://<redacted>%40github.com error") }
    end

    context "with auth in url path" do
      let(:message) do
        "Something blew up https://domain.com/token/path error"
      end

      it { is_expected.to eq("Something blew up <redacted> error") }
    end
  end
end

RSpec.describe Dependabot::DependencyFileNotFound do
  let(:error) { described_class.new(file_path) }
  let(:file_path) { "path/to/Gemfile" }

  describe "#file_name" do
    subject { error.file_name }
    it { is_expected.to eq("Gemfile") }
  end

  describe "#directory" do
    subject { error.directory }
    it { is_expected.to eq("/path/to") }

    context "with the root directory" do
      let(:file_path) { "Gemfile" }
      it { is_expected.to eq("/") }
    end

    context "with a root level file whose path starts with a slash" do
      let(:file_path) { "/Gemfile" }
      it { is_expected.to eq("/") }
    end

    context "with a nested file whose path starts with a slash" do
      let(:file_path) { "/path/to/Gemfile" }
      it { is_expected.to eq("/path/to") }
    end
  end
end

RSpec.describe Dependabot::PrivateSourceAuthenticationFailure do
  let(:error) { described_class.new(source) }
  let(:source) { "source" }

  describe "#message" do
    subject { error.message }

    it do
      is_expected.to eq(
        "The following source could not be reached as it requires authentication (and any provided details were "\
        "invalid or lacked the required permissions): source"
      )
    end

    context "when source includes something that looks like a path" do
      let(:source) do
        "source.com/token123/path"
      end

      it do
        is_expected.to eq(
          "The following source could not be reached as it requires authentication (and any provided details were "\
          "invalid or lacked the required permissions): source.com/<redacted path>"
        )
      end
    end
  end
end

RSpec.describe Dependabot::PrivateSourceTimedOut do
  let(:error) { described_class.new(source) }
  let(:source) { "source" }

  describe "#message" do
    subject { error.message }

    it do
      is_expected.to eq(
        "The following source timed out: source"
      )
    end

    context "when source includes something that looks like a path" do
      let(:source) do
        "source.com/token123/path"
      end

      it do
        is_expected.to eq(
          "The following source timed out: source.com/<redacted path>"
        )
      end
    end
  end
end

RSpec.describe Dependabot::PrivateSourceCertificateFailure do
  let(:error) { described_class.new(source) }
  let(:source) { "source" }

  describe "#message" do
    subject { error.message }

    it do
      is_expected.to eq(
        "Could not verify the SSL certificate for source"
      )
    end

    context "when source includes something that looks like a path" do
      let(:source) do
        "source.com/token123/path"
      end

      it do
        is_expected.to eq(
          "Could not verify the SSL certificate for source.com/<redacted path>"
        )
      end
    end
  end
end
