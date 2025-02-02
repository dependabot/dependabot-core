# Metadata finders

Metadata finders look up metadata about a dependency, such as its GitHub URL.

There is a `Dependabot::MetadataFinders` class for each language Dependabot
supports.

## Public API

Each `Dependabot::MetadataFinders` class exposes the following methods:

| Method                | Description                                                                                 |
|-----------------------|---------------------------------------------------------------------------------------------|
| `#source_url`         | A link to the source data for the dependency.                                               |
| `#homepage_url`       | A link to the homepage for the dependency.                                                  |
| `#commits_url`        | A link to a commit diff between the previous version of the dependency and the new version. |
| `#commits`            | A list of commits between the previous version of the dependency and the new version.       |
| `#changelog_url`      | A link to the changelog for the dependency.                                                 |
| `#changelog_text`     | The relevant text from the changelog.                                                       |
| `#release_url`        | A link to the release notes for this version of the dependency.                             |
| `#release_text`       | The relevant text from the release notes                                                    |
| `#upgrade_guide_url`  | A link to the upgrade guide for this upgrade (if it exists).                                |
| `#upgrade_guide_text` | The text of the upgrade guide for this upgrade (if it exists).                              |

An integration might look as follows:

```ruby
require 'dependabot/metadata_finders'

dependency = update_checker.updated_dependency

metadata_finder_class = Dependabot::MetadataFinders::Ruby::Bundler
metadata_finder = metadata_finder_class.new(
  dependency: dependency,
  credentials: credentials
)

puts "Changelog for #{dependency.name} is at #{metadata_finder.changelog_url}"
```

## Writing a metadata finder for a new language

All new metadata finders should inherit from `Dependabot::MetadataFinders::Base`
and implement the following methods:

| Method                 | Description             |
|------------------------|-------------------------|
| `#look_up_source`      | Private method that returns a `Dependabot::Source` object. Generally the source details are extracted from a source code URL provided by the language's dependency registry, but sometimes it's already available from parsing the dependency file. |

To ensure the above are implemented, you should include
`it_behaves_like "a dependency metadata finder"` in your specs for the new
metadata finder.

