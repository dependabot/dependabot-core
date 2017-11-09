# File parsers

File parsers take a set of dependency files and extract a list of dependencies
for the project.

There is a `Dependabot::FileParsers` class for each language Dependabot
supports.

## Public API

Each `Dependabot::FileParsers` class implements the following methods:

| Method              | Description                                                                                   |
|---------------------|-----------------------------------------------------------------------------------------------|
| `#parse`            | Returns an array of `Dependabot::Dependency` instances, representing the dependencies for the project. Each `Dependabot::Dependency` has a `name`, `version` and a `requirements` array |

An integration might look as follows:

```ruby
require 'dependabot/file_parsers'

files = fetcher.files

parser_class = Dependabot::FileParsers::Ruby::Bundler
parser = parser_class.new(dependency_files: files, repo: "gocardless/business")

dependencies = parser.parse

puts "Found the following dependencies: #{dependencies.map(&:name)}"
```

## Writing a file parser for a new language

All new file parsers should inherit from `Dependabot::FileParsers::Base` and
implement the following methods:

| Method                  | Description                                                                                   |
|-------------------------|-----------------------------------------------------------------------------------------------|
| `#parse`                | See Public API section. |
| `#check_required_files` | Raise a runtime error unless an appropriate set of files is provided. Private. |

To ensure the above are implemented, you should include
`it_behaves_like "a dependency file parser"` in your specs for the new file
parser.
