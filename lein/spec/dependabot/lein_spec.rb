# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Lein do
  it_behaves_like "it registers the required classes", "leiningen"
end
