# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Lein::FileUpdater do
  it_behaves_like "a dependency file updater"
end
