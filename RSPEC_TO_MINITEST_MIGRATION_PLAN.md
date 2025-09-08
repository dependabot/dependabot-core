# RSpec to Minitest Migration Plan for Dependabot Core

## Executive Summary

The dependabot-core repository currently uses RSpec with 534 test files across 29 ecosystems. The main driver for migration is **Sorbet's superior support for Minitest**, which will enable better type checking in test files (currently all test files are ignored by Sorbet).

## Current State Analysis

### Test Infrastructure Overview

- **534 test files** (`*_spec.rb`) across 29 ecosystems
- **Common ecosystem** has the most tests (68 files), followed by **npm_and_yarn** (44), **python** (36), and **bundler** (34)
- Uses **RSpec 3.12+** with extensive shared examples and complex test patterns
- Tests are **containerized** and run via Docker with `turbo_tests` for parallelization
- **All test files are `# typed: false`** and ignored by Sorbet (see `sorbet/config`)

### Test File Distribution by Ecosystem

```text
bin: 1              | conda: 12           | gradle: 19
nuget: 3            | helm: 12            | hex: 19
docker_compose: 4   | pub: 12             | cargo: 22
vcpkg: 8            | rust_toolchain: 12  | maven: 23
devcontainers: 9    | terraform: 13       | uv: 26
dotnet_sdk: 9       | bun: 15             | updater: 33
git_submodules: 10  | go_modules: 15      | bundler: 34
docker: 11          | elm: 16             | python: 36
github_actions: 11  | composer: 19        | npm_and_yarn: 44
swift: 11           |                     | common: 68
```

### Key RSpec Features Currently Used

- **Shared examples** (`shared_examples`, `it_behaves_like`)
- **Complex mocking** with RSpec mocks (`allow`, `expect`, `double`, `stub`)
- **Rich DSL** (`describe`, `context`, `it`, `let`, `let!`, `subject`, `before`, `after`)
- **`described_class`** for class under test references
- **`its`** for property testing via `rspec-its` gem
- **VCR integration** for HTTP cassette recording
- **Custom matchers** and test helpers

### Current Dependencies

```ruby
# common/dependabot-common.gemspec
spec.add_development_dependency "rspec", "~> 3.12"
spec.add_development_dependency "rspec-its", "~> 1.3"
spec.add_development_dependency "rspec-sorbet", "~> 1.9"
```

## Migration Strategy

### Phase 1: Foundation & Proof of Concept (2-3 weeks)

#### 1.1 Add Minitest Dependencies (Keep RSpec)

**Add Minitest dependencies alongside existing RSpec:**

```ruby
# common/dependabot-common.gemspec - ADD these lines (keep existing RSpec):
spec.add_development_dependency "minitest", "~> 5.20"
spec.add_development_dependency "minitest-reporters", "~> 1.6"

# Keep existing RSpec dependencies during migration:
# spec.add_development_dependency "rspec", "~> 3.12"
# spec.add_development_dependency "rspec-its", "~> 1.3"
# spec.add_development_dependency "rspec-sorbet", "~> 1.9"
```

#### 1.2 Create Minitest Infrastructure

**Main test helper:**

```ruby
# common/test/test_helper.rb
# typed: strict
# frozen_string_literal: true

require "minitest/autorun"
require "minitest/reporters"
require "webmock/minitest"
require "vcr"
require "debug"
require "simplecov"

# Use progress reporter for clean output
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

# Sorbet-compatible test_each methods for table-driven tests
sig do
  type_parameters(:U)
    .params(iter: T::Enumerable[T.type_parameter(:U)],
            blk: T.proc.params(arg0: T.type_parameter(:U)).void)
    .void
end
def self.test_each(iter, &blk)
  iter.each(&blk)
end

sig do
  type_parameters(:K, :V)
    .params(hash: T::Hash[T.type_parameter(:K), T.type_parameter(:V)],
            blk: T.proc.params(arg0: [T.type_parameter(:K), T.type_parameter(:V)]).void)
    .void
end
def self.test_each_hash(hash, &blk)
  hash.each(&blk)
end

# VCR configuration (keeping existing setup)
VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  # ... existing VCR config
end

# Helper methods (ported from spec_helper.rb)
def fixture(*name)
  File.read(File.join("test", "fixtures", File.join(*name)))
end

# ... other helper methods
```

**Ecosystem-specific test helpers:**

```ruby
# bundler/test/test_helper.rb
# typed: strict
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_test(path)
  require "#{common_dir}/test/dependabot/#{path}"
end

require "#{common_dir}/test/test_helper.rb"

# Ecosystem-specific helpers
module PackageManagerHelper
  # ... ported from spec_helper.rb
end
```

#### 1.3 Pilot Migration & Coexistence Testing

**Target:** Start with smallest ecosystem (bin/ - 1 file or nuget/ - 3 files)

**Directory structure during migration:**

```text
bin/
├── spec/
│   └── dependabot/
│       └── dry_run_spec.rb      # Keep existing RSpec tests
└── test/
    └── dependabot/
        └── dry_run_test.rb      # Add new Minitest tests
```

**Validation steps:**

1. Both test suites run successfully
2. Test coverage remains identical
3. CI pipeline handles both frameworks
4. No interference between test frameworks

### Phase 2: Core Ecosystem Migration (4-6 weeks)

#### 2.1 Migrate Common Ecosystem First

The `common/` ecosystem serves as the foundation for all others and contains shared examples that need conversion.

**Convert shared examples to modules:**

```ruby
# Before (RSpec):
# common/spec/dependabot/shared_examples_for_autoloading.rb
RSpec.shared_examples "it registers the required classes" do |pckg_mngr|
  it "registers a file fetcher" do
    klass = Dependabot::FileFetchers.for_package_manager(pckg_mngr)
    expect(klass.ancestors).to include(Dependabot::FileFetchers::Base)
  end
  # ... more tests
end

# After (Minitest):
# common/test/dependabot/shared_autoloading_tests.rb
module SharedAutoloadingTests
  extend T::Sig

  sig { params(test_case: Minitest::Test, pckg_mngr: String).void }
  def self.test_registrations(test_case, pckg_mngr)
    test_case.define_singleton_method("test_#{pckg_mngr}_registers_file_fetcher") do
      klass = Dependabot::FileFetchers.for_package_manager(pckg_mngr)
      assert_includes(klass.ancestors, Dependabot::FileFetchers::Base)
    end
    # ... define more test methods
  end
end

# Usage in test:
class BundlerAutoloadingTest < Minitest::Test
  def setup
    SharedAutoloadingTests.test_registrations(self, "bundler")
  end
end
```

#### 2.2 Establish Core Conversion Patterns

**Basic RSpec → Minitest conversions:**

| RSpec Pattern | Minitest Pattern | Notes |
|---------------|------------------|-------|
| `describe "Class"` | `class ClassTest < Minitest::Test` | Convert to test class |
| `context "when X"` | `# when X` (comment) | Use comments for context |
| `it "does something"` | `def test_does_something` | Convert to test method |
| `let(:var) { value }` | `def setup; @var = value; end` | Use setup method |
| `subject { Class.new }` | `def setup; @subject = Class.new; end` | Use setup method |
| `before { setup }` | `def setup; ...; end` | Use setup method |
| `after { cleanup }` | `def teardown; ...; end` | Use teardown method |
| `described_class` | `ExplicitClassName` | Manual replacement needed |
| `expect(x).to eq(y)` | `assert_equal(y, x)` | Classic assertion style |
| `expect { }.to raise_error` | `assert_raises { }` | Exception testing |
| `expect(x).to be_truthy` | `assert(x)` | Boolean assertions |

**Example conversion:**

```ruby
# Before (RSpec):
RSpec.describe Dependabot::FileParsers::Base::DependencySet do
  let(:dependency_set) { described_class.new }

  describe ".new" do
    context "with no argument" do
      subject { described_class.new }

      it { is_expected.to be_a(described_class) }
      its(:dependencies) { is_expected.to eq([]) }
    end
  end
end

# After (Minitest):
class DependencySetTest < Minitest::Test
  def setup
    @dependency_set = Dependabot::FileParsers::Base::DependencySet.new
  end

  def test_new_with_no_argument_creates_dependency_set
    subject = Dependabot::FileParsers::Base::DependencySet.new

    assert_instance_of(Dependabot::FileParsers::Base::DependencySet, subject)
    assert_equal([], subject.dependencies)
  end
end
end
```

#### 2.3 Handle Sorbet Typing

**Enable strict typing in test files:**

```ruby
# typed: strict
# frozen_string_literal: true

require "test_helper"

class FileParserTest < Minitest::Test
  extend T::Sig

  sig { void }
  def setup
    @files = T.let([
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler", "gemfiles", "Gemfile")
      )
    ], T::Array[Dependabot::DependencyFile])

    @source = T.let(Dependabot::Source.new(
      provider: "github",
      repo: "example/repo"
    ), Dependabot::Source)
  end

  sig { void }
  def test_parses_dependencies_correctly
    parser = Dependabot::Bundler::FileParser.new(
      dependency_files: @files,
      source: @source
    )

    dependencies = parser.parse
    assert_instance_of(Array, dependencies)
  end
end
      provider: "github",
      repo: "example/repo"
    )
  end
end
```

### Phase 3: Bulk Migration (6-8 weeks)

#### 3.1 Migration Order by Complexity

**Simple ecosystems (1-2 weeks each):**

- docker (11 files)
- elm (16 files)
- git_submodules (10 files)
- github_actions (11 files)
- swift (11 files)

**Medium ecosystems (1-3 weeks each):**

- cargo (22 files)
- composer (19 files)
- gradle (19 files)
- maven (23 files)
- go_modules (15 files)

**Complex ecosystems (2-4 weeks each):**

- bundler (34 files) - many complex patterns
- npm_and_yarn (44 files) - largest ecosystem
- python (36 files) - complex dependency handling

#### 3.2 Automated Conversion Tools

**Create migration script for common patterns:**

```ruby
#!/usr/bin/env ruby
# script/migrate_ecosystem_to_minitest.rb

require "fileutils"

class RSpecToMinitestMigrator
  def initialize(ecosystem_path)
    @ecosystem_path = ecosystem_path
    @spec_dir = File.join(ecosystem_path, "spec")
    @test_dir = File.join(ecosystem_path, "test")
  end

  def migrate!
    return unless Dir.exist?(@spec_dir)

    puts "Migrating #{@ecosystem_path}..."

    # Create test directory structure alongside existing spec/
    FileUtils.mkdir_p(@test_dir)

    # Convert each spec file (keeps original spec files)
    Dir.glob("#{@spec_dir}/**/*_spec.rb").each do |spec_file|
      convert_spec_file(spec_file)
    end

    # Create test_helper.rb
    create_test_helper

    puts "Migration complete!"
    puts "ℹ️  Original spec/ directory preserved for parallel testing"
    puts "ℹ️  Remove spec/ directory only after migration is validated"
  end

  private

  def convert_spec_file(spec_file)
    content = File.read(spec_file)

    # Basic conversions for MiniTest::Unit style
    content.gsub!(/require "spec_helper"/, 'require "test_helper"')

    # Convert RSpec.describe to class declarations
    content.gsub!(/RSpec\.describe\s+([^\s]+).*do/, 'class \1Test < Minitest::Test')

    # Convert describe blocks to comments
    content.gsub!(/\s*describe\s+"([^"]+)".*do/, "\n  # \\1")
    content.gsub!(/\s*context\s+"([^"]+)".*do/, "\n  # when \\1")

    # Convert it blocks to test methods
    content.gsub!(/\s*it\s+"([^"]+)".*do/, "\n  def test_\\1")
    content.gsub!(/\s*it\s+\{[^}]+\}/, '  # TODO: Convert one-liner test')

    # Convert let to setup method (needs manual review)
    if content.include?("let(")
      content.gsub!(/\s*let\([^)]+\).*\n/, "  # TODO: Move to setup method\n")
      puts "⚠️  Manual review needed: #{spec_file} contains let() - move to setup method"
    end

    # Convert expectations to assertions
    content.gsub!(/expect\((.*?)\)\.to eq\((.*?)\)/, 'assert_equal(\\2, \\1)')
    content.gsub!(/expect\((.*?)\)\.to be_truthy/, 'assert(\\1)')
    content.gsub!(/expect\((.*?)\)\.to be_falsy/, 'refute(\\1)')
    content.gsub!(/expect\((.*?)\)\.to be_nil/, 'assert_nil(\\1)')
    content.gsub!(/expect\((.*?)\)\.to be_instance_of\((.*?)\)/, 'assert_instance_of(\\2, \\1)')
    content.gsub!(/expect\s*\{\s*(.*?)\s*\}\.to raise_error/, 'assert_raises { \\1 }')

    # Handle described_class (requires manual review)
    if content.include?("described_class")
      content.gsub!(/described_class/, "REPLACE_WITH_ACTUAL_CLASS_NAME")
      puts "⚠️  Manual review needed: #{spec_file} contains described_class"
    end

    # Create corresponding test file
    test_file = spec_file.gsub(@spec_dir, @test_dir).gsub(/_spec\.rb$/, "_test.rb")
    FileUtils.mkdir_p(File.dirname(test_file))
    File.write(test_file, content)

    puts "✓ Converted #{spec_file} → #{test_file}"
    puts "⚠️  Manual review recommended: Check method names and setup/teardown"
  end

  def create_test_helper
    helper_content = <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      def common_dir
        @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
      end

      def require_common_test(path)
        require "\#{common_dir}/test/dependabot/\#{path}"
      end

      require "\#{common_dir}/test/test_helper.rb"
    RUBY

    File.write(File.join(@test_dir, "test_helper.rb"), helper_content)
  end
end

# Usage: ruby script/migrate_ecosystem_to_minitest.rb bundler
ecosystem = ARGV[0]
if ecosystem && Dir.exist?(ecosystem)
  RSpecToMinitestMigrator.new(ecosystem).migrate!
else
  puts "Usage: ruby script/migrate_ecosystem_to_minitest.rb <ecosystem_name>"
  puts "Available ecosystems: #{Dir.glob("*/").select { |d| Dir.exist?(File.join(d, "spec")) }.map { |d| d.chomp("/") }.join(", ")}"
end
```

### Phase 4: Infrastructure Updates (2-3 weeks)

#### 4.1 Update Build/CI Systems

##### During migration: Run both RSpec and Minitest in parallel

```yaml
# .github/workflows/ci.yml - During migration phase
- name: Run ${{ matrix.suite.name }} RSpec tests
  if: steps.changes.outputs[matrix.suite.path] == 'true'
  run: |
    docker run \
      --pull never \
      --env "CI=true" \
      --env "RAISE_ON_WARNINGS=true" \
      --env "DEPENDABOT_TEST_ACCESS_TOKEN=${{ secrets.GITHUB_TOKEN }}" \
      --env "SUITE_NAME=${{ matrix.suite.name }}" \
      --rm ghcr.io/dependabot/dependabot-updater-${{ matrix.suite.ecosystem }} bash -c \
      "cd /home/dependabot/${{ matrix.suite.path }} && bundle exec rspec"

- name: Run ${{ matrix.suite.name }} Minitest tests (if migrated)
  if: steps.changes.outputs[matrix.suite.path] == 'true'
  continue-on-error: true  # Allow failures during migration
  run: |
    docker run \
      --pull never \
      --env "CI=true" \
      --env "RAISE_ON_WARNINGS=true" \
      --env "DEPENDABOT_TEST_ACCESS_TOKEN=${{ secrets.GITHUB_TOKEN }}" \
      --env "SUITE_NAME=${{ matrix.suite.name }}" \
      --rm ghcr.io/dependabot/dependabot-updater-${{ matrix.suite.ecosystem }} bash -c \
      "cd /home/dependabot/${{ matrix.suite.path }} && if [ -d test ]; then rake test; fi"
```

##### After migration: Switch to Minitest only

```yaml
# .github/workflows/ci.yml - After migration complete
- name: Run ${{ matrix.suite.name }} tests
  if: steps.changes.outputs[matrix.suite.path] == 'true'
  run: |
    docker run \
      --pull never \
      --env "CI=true" \
      --env "RAISE_ON_WARNINGS=true" \
      --env "DEPENDABOT_TEST_ACCESS_TOKEN=${{ secrets.GITHUB_TOKEN }}" \
      --env "SUITE_NAME=${{ matrix.suite.name }}" \
      --rm ghcr.io/dependabot/dependabot-updater-${{ matrix.suite.ecosystem }} bash -c \
      "cd /home/dependabot/${{ matrix.suite.path }} && rake test"
```

#### 4.2 Update Rake Tasks

**Replace script/ci-test in each ecosystem:**

##### During migration: Support both RSpec and Minitest

```bash
#!/usr/bin/env bash
# script/ci-test - During migration

set -e

bundle install

# Run RSpec tests (existing)
if [ -d spec ]; then
  echo "Running RSpec tests..."
  bundle exec rspec
fi

# Run Minitest tests (if migrated)
if [ -d test ]; then
  echo "Running Minitest tests..."
  bundle exec rake test
fi
```

##### After migration: Minitest only

```bash
#!/usr/bin/env bash
# script/ci-test - After migration complete

set -e

bundle install
bundle exec rake test
```

**Update Rakefile in each ecosystem:**

```ruby
# Add to each ecosystem's Rakefile - supports both during migration
require "rake/testtask"

# Minitest task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
  t.verbose = true
end

# Keep RSpec task during migration (remove after completion)
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # RSpec not available - migration complete
end

# Default task runs appropriate test suite
task :default do
  if Dir.exist?("test") && !Dir.glob("test/**/*_test.rb").empty?
    Rake::Task[:test].invoke
  elsif Dir.exist?("spec") && !Dir.glob("spec/**/*_spec.rb").empty?
    Rake::Task[:spec].invoke
  else
    puts "No tests found"
  end
end
```

#### 4.3 Remove RSpec Dependencies (Final Step)

**Only after ALL ecosystems are migrated:**

```ruby
# common/dependabot-common.gemspec - REMOVE these lines:
# spec.add_development_dependency "rspec", "~> 3.12"
# spec.add_development_dependency "rspec-its", "~> 1.3"
# spec.add_development_dependency "rspec-sorbet", "~> 1.9"
```

**Clean up spec directories:**

```bash
# Remove all spec/ directories after migration is complete
find . -name "spec" -type d -exec rm -rf {} +
```

#### 4.4 Update Sorbet Configuration

**Enable type checking for test files:**

```diff
# sorbet/config
--dir=.
--ignore=tmp/
--ignore=vendor/
--ignore=.bundle/
--ignore=bin
--disable-watchman

-# Sorbet doesn't currently support RSpec very well, so we ignore all of our specs.
-# See https://stackoverflow.com/a/76548429
---ignore=bun/spec/
---ignore=bundler/helpers
---ignore=bundler/spec/
-# ... (remove all --ignore=*/spec/ lines)

# Keep helper ignores
--ignore=bundler/helpers
--ignore=.git
```

## Technical Challenges & Solutions

### 1. Shared Examples Migration

**Challenge:** RSpec's `shared_examples` pattern doesn't exist in Minitest

**Solution:** Convert to Ruby modules that define test methods dynamically

```ruby
# Before (RSpec shared example):
RSpec.shared_examples "file fetcher behavior" do |package_manager|
  it "fetches the expected files" do
    expect(fetcher.files.map(&:name)).to include("Gemfile")
  end
end

# After (Minitest module):
module SharedFileFetcherTests
  extend T::Sig

  sig { params(test_case: Minitest::Test, package_manager: String).void }
  def self.include_file_fetcher_tests(test_case, package_manager)
    test_case.define_singleton_method("test_#{package_manager}_fetches_expected_files") do
      fetcher = create_fetcher_for(package_manager)
      assert_includes(fetcher.files.map(&:name), "Gemfile")
    end
  end
end

# Usage in test:
class BundlerFileFetcherTest < Minitest::Test
  def setup
    SharedFileFetcherTests.include_file_fetcher_tests(self, "bundler")
  end

  private

  def create_fetcher_for(package_manager)
    # Create and return appropriate fetcher
  end
end
```

### 2. Complex Mocking Patterns

**Challenge:** RSpec mocks are more sophisticated than Minitest mocks

**Solutions:**

**Simple mocking** - Use `minitest/mock`:

```ruby
# RSpec
allow(object).to receive(:method).and_return(value)

# Minitest
def test_with_mocking
  object = SomeClass.new
  object.stub(:method, "mocked_value") do
    result = object.method
    assert_equal("mocked_value", result)
  end
end
```

**HTTP mocking** - Keep `webmock` (already compatible):

```ruby
# Works the same in both
stub_request(:get, "https://example.com").to_return(body: "response")
```

**Complex mocking** - Consider adding `mocha` gem if needed:

```ruby
# Gemfile addition for complex cases
gem "mocha", "~> 2.1", group: :test
```

### 3. `described_class` Replacement

**Challenge:** Minitest doesn't have `described_class` equivalent

**Solution:** Manual replacement with explicit class names

```ruby
# Before (RSpec):
RSpec.describe Dependabot::Bundler::FileParser do
  let(:parser) { described_class.new(files: files) }

  it "parses correctly" do
    expect(described_class.new).to be_a(described_class)
  end
end

# After (Minitest):
class BundlerFileParserTest < Minitest::Test
  def setup
    @files = create_test_files
    @parser = Dependabot::Bundler::FileParser.new(files: @files)
  end

  def test_parses_correctly
    parser = Dependabot::Bundler::FileParser.new(files: @files)
    assert_instance_of(Dependabot::Bundler::FileParser, parser)
  end

  private

  def create_test_files
    # Create test dependency files
  end
end
  end
end
```

**Alternative:** Create helper method:

```ruby
class BaseMinitest < Minitest::Spec
  def self.described_class
    # Extract class name from test class name
    # BundlerFileParserTest → Dependabot::Bundler::FileParser
    name.gsub(/Test$/, '').gsub(/([A-Z])/, '::\1')[2..-1]
  end
end
```

### 4. Table-Driven Tests with Sorbet

**Challenge:** RSpec's dynamic `each` blocks don't work with Sorbet in Minitest

**Solution:** Use Sorbet's recommended `test_each` pattern or explicit test methods

```ruby
# Before (RSpec):
VERSIONS.each do |version|
  it "works with version #{version}" do
    expect(parser.parse_version(version)).to be_valid
  end
end

# After (Minitest with Sorbet):
class VersionParserTest < Minitest::Test
  extend T::Sig

  VERSIONS = T.let(["1.0.0", "2.0.0", "3.0.0"], T::Array[String])

  sig { void }
  def test_version_parsing
    test_each(VERSIONS) do |version|
      parser = create_parser
      result = parser.parse_version(version)
      assert(result.valid?, "Version #{version} should be valid")
    end
  end

  private

  sig { returns(VersionParser) }
  def create_parser
    VersionParser.new
  end
end
```

### 5. Custom Matchers

**Challenge:** RSpec custom matchers need conversion

**Solution:** Convert to helper methods or custom assertions

```ruby
# Before (RSpec matcher):
RSpec::Matchers.define :be_valid_version do
  match { |actual| actual.is_a?(Gem::Version) }
end

expect(version).to be_valid_version

# After (Minitest helper):
class VersionTest < Minitest::Test
  def test_version_validation
    version = parse_version("1.0.0")
    assert_valid_version(version)
  end

  private

  def assert_valid_version(version)
    assert_instance_of(Gem::Version, version)
  end
end

## Benefits of Migration

### 1. Sorbet Type Checking

- Enable `# typed: strict` in test files with MiniTest::Unit's simple class structure
- Better IDE support with autocomplete and error detection
- Catch type errors at static analysis time instead of runtime

### 2. Simpler Test Framework

- **MiniTest::Unit is "just Ruby"** - plain classes and methods, no DSL magic
- **Classic assertion style** - `assert_equal`, `assert_nil`, etc. are clear and direct
- **Less magic and metaprogramming** compared to RSpec's extensive DSL
- **Fewer abstractions** between test code and Ruby
- **Easier debugging** with standard Ruby stack traces and familiar method calls

### 3. Better Performance

- Minitest generally has faster startup time than RSpec
- Less memory overhead
- Simpler test runner

### 4. Consistency with Ruby Ecosystem

- Rails uses Minitest by default
- Many Ruby gems use Minitest
- Aligns with Ruby's philosophy of simplicity

### 5. Reduced Dependencies

- Smaller gem footprint
- Fewer transitive dependencies
- Simpler dependency management

### 6. Enhanced Maintainability

- Type-checked test code reduces bugs
- Clearer test structure with explicit typing
- Better refactoring support with type information

## Risk Mitigation Strategies

### 1. Gradual Migration Approach

- Migrate ecosystem by ecosystem to minimize risk
- Keep both RSpec and Minitest working during transition
- Roll back individual ecosystems if issues arise

### 2. Comprehensive Testing

- **Run both test suites in parallel** throughout the migration to ensure no regressions
- **Keep existing RSpec dependencies** until migration is complete for each ecosystem
- **Automated comparison of test results** between RSpec and Minitest outputs
- **Per-ecosystem validation** - migrate one ecosystem at a time while others remain on RSpec
- Extensive CI testing on all supported platforms

### 3. Automated Conversion Scripts

- Reduce manual errors with scripted conversion
- Consistent patterns across all ecosystems
- Ability to re-run conversion if needed

### 4. Documentation and Training

- Clear migration guides for contributors
- Examples of common patterns
- Best practices for Minitest + Sorbet

### 5. Test Coverage Monitoring

- Ensure no functionality is lost during conversion
- Monitor test execution times
- Verify all edge cases are still covered

### 6. Rollback Plan

- Keep RSpec configuration available
- Document rollback procedures
- Ability to revert individual ecosystems

## Timeline and Resource Estimates

### Total Duration: 12-15 weeks (3-4 months)

#### Phase 1: Foundation & Proof of Concept

- **Duration:** 2-3 weeks
- **Resources:** 1 developer
- **Deliverables:**
  - Minitest infrastructure
  - Pilot ecosystem migration (bin/ or nuget/)
  - Conversion scripts

#### Phase 2: Core Ecosystem Migration

- **Duration:** 4-6 weeks
- **Resources:** 2-3 developers
- **Deliverables:**
  - Common ecosystem migrated
  - Shared test patterns established
  - Sorbet typing guidelines

#### Phase 3: Bulk Migration

- **Duration:** 6-8 weeks
- **Resources:** 2-4 developers
- **Deliverables:**
  - All remaining ecosystems migrated
  - Test coverage maintained
  - Performance benchmarking

#### Phase 4: Infrastructure Updates

- **Duration:** 2-3 weeks
- **Resources:** 1-2 developers
- **Deliverables:**
  - CI/CD pipeline updated
  - Documentation completed
  - Final validation

### Success Criteria

1. ✅ **All 534 test files successfully converted and passing**
2. ✅ **Sorbet type checking enabled for test files (`# typed: strict`)**
3. ✅ **CI/CD pipeline updated and working reliably**
4. ✅ **Test execution time maintained or improved**
5. ✅ **No loss of test coverage or functionality**
6. ✅ **Developer experience improved with better IDE support**
7. ✅ **Documentation and examples provided for future contributors**

## Conclusion

This migration from RSpec to Minitest represents a significant but worthwhile investment in the long-term maintainability and type safety of the Dependabot Core test suite. The primary benefit of enabling Sorbet's type checking in test files will improve developer productivity and reduce bugs.

The phased approach minimizes risk while ensuring thorough testing and validation at each step. With proper planning and execution, this migration will align Dependabot Core with modern Ruby best practices and Sorbet's strengths.

The estimated 3-4 month timeline allows for careful execution while maintaining the high quality standards expected of the Dependabot project.
