# frozen_string_literal: true

require "dependabot/file_fetchers/elm/elm_package"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Elm::ElmPackage do
  it_behaves_like "a dependency file fetcher"
end
