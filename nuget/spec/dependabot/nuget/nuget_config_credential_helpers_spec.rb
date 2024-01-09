# typed: false
# frozen_string_literal: true

require "dependabot/nuget/nuget_config_credential_helpers"

RSpec.describe Dependabot::Nuget::NuGetConfigCredentialHelpers do
  let(:user_nuget_config_contents_during_and_after_action) do
    path = Dependabot::Nuget::NuGetConfigCredentialHelpers.user_nuget_config_path
    content_during_action = nil
    Dependabot::Nuget::NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials, lambda {
      content_during_action = File.read(path)
    })
    content_after_action = File.read(path)
    { content_during_action: content_during_action, content_after_action: content_after_action }
  end

  subject(:result) { user_nuget_config_contents_during_and_after_action }

  describe "user level NuGet.Config patching" do
    context "with an empty credential set" do
      let(:credentials) { [] }

      it "does not change the contents of the file" do
        expect(result[:content_during_action]).to include("https://api.nuget.org/v3/index.json")
        expect(result[:content_after_action]).to include("https://api.nuget.org/v3/index.json")
      end
    end

    context "with non-empty credential set" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://nuget.example.com/index.json", "token" => "secret_token" }]
      end

      context "with credentials given" do
        it "changes the content of the config file, then changes it back" do
          expect(result[:content_during_action]).to include("https://nuget.example.com/index.json")
          expect(result[:content_during_action]).not_to include("https://api.nuget.org/v3/index.json")

          expect(result[:content_after_action]).not_to include("https://nuget.example.com/index.json")
          expect(result[:content_after_action]).to include("https://api.nuget.org/v3/index.json")
        end
      end

      context "when exception is raised" do
        it "restores the original file after an exception" do
          Dependabot::Nuget::NuGetConfigCredentialHelpers.patch_nuget_config_for_action(
            credentials,
            lambda {
              raise "This exception was raised when the NuGet.Config file was patched"
            }
          )
          nuget_config_content = File.read(Dependabot::Nuget::NuGetConfigCredentialHelpers.user_nuget_config_path)
          expect(nuget_config_content).not_to include("https://nuget.example.com/index.json")
          expect(nuget_config_content).to include("https://api.nuget.org/v3/index.json")
        end
      end
    end
  end
end
