---
applyTo:
  - "**/file_fetcher.rb"
  - "**/file_fetcher/**"
  - "**/file_parser.rb"
  - "**/file_parser/**"
  - "**/file_updater.rb"
  - "**/file_updater/**"
  - "**/update_checker.rb"
  - "**/update_checker/**"
  - "**/metadata_finder.rb"
  - "**/metadata_finder/**"
  - "**/version.rb"
  - "**/requirement.rb"
---

# Core Class Structure Pattern

**CRITICAL**: All Dependabot core classes with nested helper classes must follow the exact pattern to avoid "superclass mismatch" errors. This pattern is used consistently across all established ecosystems (bundler, npm_and_yarn, go_modules, etc.).

## Main Class Structure

Applies to FileFetcher, FileParser, FileUpdater, UpdateChecker, etc.

```ruby
# {ecosystem}/lib/dependabot/{ecosystem}/file_updater.rb (or file_fetcher.rb, file_parser.rb, etc.)
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module {Ecosystem}
    class FileUpdater < Dependabot::FileUpdaters::Base
      # require_relative statements go INSIDE the class
      require_relative "file_updater/helper_class"

      # Main logic here...
    end
  end
end

Dependabot::FileUpdaters.register("{ecosystem}", Dependabot::{Ecosystem}::FileUpdater)
```

## Helper Class Structure

```ruby
# {ecosystem}/lib/dependabot/{ecosystem}/file_updater/helper_class.rb
require "dependabot/{ecosystem}/file_updater"

module Dependabot
  module {Ecosystem}
    class FileUpdater < Dependabot::FileUpdaters::Base
      class HelperClass
        # Helper logic nested INSIDE the main class
      end
    end
  end
end
```

## Key Rules

1. **Main classes** inherit from appropriate base: `Dependabot::FileUpdaters::Base`, `Dependabot::FileFetchers::Base`, etc.
2. **Helper classes** are nested inside the main class.
3. **`require_relative`** statements go INSIDE the main class, not at module level.
4. **Helper classes require the main file** first: `require "dependabot/{ecosystem}/file_updater"`.
5. **Never define multiple top-level classes** with the same name in the same namespace.
6. **Backward compatibility** can use static methods that delegate to instance methods.

## Applies To

- **FileFetcher** and its helpers (e.g., `FileFetcher::GitCommitChecker`)
- **FileParser** and its helpers (e.g., `FileParser::ManifestParser`)
- **FileUpdater** and its helpers (e.g., `FileUpdater::LockfileUpdater`)
- **UpdateChecker** and its helpers (e.g., `UpdateChecker::VersionResolver`)
- **MetadataFinder** and its helpers
- **Version** and **Requirement** classes (if they have nested classes)
