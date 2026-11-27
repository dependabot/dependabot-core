import json

from lib.poetry_pyproject_editor import update_poetry_declarations


def edit(content, name, group, old, new, **extra):
    change = {
        "name": name,
        "group": group,
        "old_requirement": old,
        "new_requirement": new,
        **extra,
    }
    result = json.loads(update_poetry_declarations(content, [change]))
    return result["result"]["content"], result["result"]["applied"][0]


class TestPoetryTables:
    def test_keeps_comments_and_quote_style(self):
        content = (
            "[tool.poetry.dependencies]\n"
            "python = \"^3.9\"\n"
            "# pinned for reasons\n"
            "requests = '^2.0'  # keep me\n"
        )

        new, applied = edit(
            content, "requests", "dependencies", "^2.0", "^2.32"
        )

        assert applied
        assert new == content.replace("'^2.0'", "'^2.32'")

    def test_inline_table_keeps_extras(self):
        content = (
            "[tool.poetry.dependencies]\n"
            "foo = { version = \"^1.0\", extras = [\"bar\"] }  # c\n"
        )

        new, _ = edit(content, "foo", "dependencies", "^1.0", "^1.5")

        assert new == content.replace("^1.0", "^1.5")

    def test_super_table_declaration(self):
        content = (
            "[tool.poetry.dependencies.foo]\n"
            "version = \"1.0\"   # trailing\n"
            "extras = [\"bar\"]\n"
        )

        new, _ = edit(content, "foo", "dependencies", "1.0", "2.0")

        assert new == content.replace("\"1.0\"", "\"2.0\"")

    def test_only_the_matching_multiple_constraint_entry(self):
        content = (
            "[tool.poetry.dependencies]\n"
            "numpy = [\n"
            "  {version = \"^1.21\", python = \"<3.11\"},  # old\n"
            "  {version = \"^1.26\", python = \">=3.11\"},\n"
            "]\n"
        )

        new, _ = edit(content, "numpy", "dependencies", "^1.26", "^2.0")

        assert new == content.replace("^1.26", "^2.0")

    def test_matches_names_after_pep503_normalisation(self):
        content = "[tool.poetry.dependencies]\nZope_Interface = \"^5\"\n"

        new, _ = edit(content, "zope-interface", "dependencies", "^5", "^6")

        assert new == "[tool.poetry.dependencies]\nZope_Interface = \"^6\"\n"

    def test_named_group_and_legacy_dev_table(self):
        content = (
            "[tool.poetry.dev-dependencies]\n"
            "pytest = \"^7\"\n\n"
            "[tool.poetry.group.lint.dependencies]\n"
            "pytest = \"^7\"\n"
        )

        new, _ = edit(content, "pytest", "lint", "^7", "^8")

        assert new == (
            "[tool.poetry.dev-dependencies]\n"
            "pytest = \"^7\"\n\n"
            "[tool.poetry.group.lint.dependencies]\n"
            "pytest = \"^8\"\n"
        )

    def test_does_not_touch_a_prefix_match(self):
        # The regex updater does a substring replace once it finds the line.
        content = "[tool.poetry.dependencies]\nfoo = \"^1.0.1\"\n"

        new, applied = edit(content, "foo", "dependencies", "1.0", "2.0")

        assert not applied
        assert new == content

    def test_git_tag(self):
        content = (
            "[tool.poetry.dependencies]\n"
            "fastapi = { git = \"https://x/fastapi\", tag = \"0.110.0\" }\n"
        )
        change = {
            "name": "fastapi", "group": "dependencies",
            "old_tag": "0.110.0", "new_tag": "0.111.0",
        }

        result = json.loads(update_poetry_declarations(content, [change]))

        assert result["result"]["content"] == content.replace(
            "0.110.0", "0.111.0"
        )


class TestPep508Arrays:
    def test_project_dependencies_keep_spacing_and_markers(self):
        content = (
            "[project]\n"
            "dependencies = [\n"
            "  \"attrs >= 21.0, <23\",  # attrs\n"
            "  'six==1.0 ; python_version < \"3\"',\n"
            "]\n"
        )

        new, _ = edit(
            content, "attrs", "dependencies", "<23,>=21.0", "<23,>=22.0"
        )
        new, _ = edit(new, "six", "dependencies", "==1.0", "==1.1")

        assert new == (
            "[project]\n"
            "dependencies = [\n"
            "  \"attrs >= 22.0, <23\",  # attrs\n"
            "  'six==1.1 ; python_version < \"3\"',\n"
            "]\n"
        )

    def test_extras_must_match(self):
        content = (
            "[project]\n"
            "dependencies = [\"cachecontrol>=0.13\", "
            "\"CacheControl[filecache]>=0.13\"]\n"
        )

        new, _ = edit(
            content, "cachecontrol", "dependencies", ">=0.13", ">=0.14",
            extras=["filecache"],
        )

        assert new == content.replace(
            "CacheControl[filecache]>=0.13", "CacheControl[filecache]>=0.14"
        )

    def test_optional_dependencies_and_dependency_groups(self):
        content = (
            "[project.optional-dependencies]\n"
            "socks = [\"PySocks>=1.5.6\"]\n\n"
            "[dependency-groups]\n"
            "test = [{include-group = \"lint\"}, \"pytest>=7\"]\n"
        )

        new, _ = edit(content, "pysocks", "socks", ">=1.5.6", ">=1.7.1")
        new, _ = edit(new, "pytest", "test", ">=7", ">=8")

        assert new == (
            "[project.optional-dependencies]\n"
            "socks = [\"PySocks>=1.7.1\"]\n\n"
            "[dependency-groups]\n"
            "test = [{include-group = \"lint\"}, \"pytest>=8\"]\n"
        )

    def test_replaces_whole_specifier_when_operators_change(self):
        content = "[project]\ndependencies = [\"foo~=1.0\"]\n"

        new, _ = edit(content, "foo", "dependencies", "~=1.0", ">=1.0,<3")

        assert new == "[project]\ndependencies = [\"foo>=1.0,<3\"]\n"

    def test_poetry_table_wins_over_project_table(self):
        content = (
            "[project]\ndependencies = [\"foo==1.0\"]\n\n"
            "[tool.poetry.dependencies]\nfoo = \"==1.0\"\n"
        )

        first, _ = edit(content, "foo", "dependencies", "==1.0", "==2.0")
        second, _ = edit(first, "foo", "dependencies", "==1.0", "==2.0")

        assert first == content.replace("foo = \"==1.0\"", "foo = \"==2.0\"")
        assert second == content.replace("1.0", "2.0")


def test_reports_unapplied_edits():
    content = "[tool.poetry.dependencies]\nfoo = \"^1\"\n"
    changes = [
        {"name": "bar", "group": "dependencies",
         "old_requirement": "^1", "new_requirement": "^2"},
        {"name": "foo", "group": "dependencies",
         "old_requirement": "^1", "new_requirement": "^2"},
    ]

    result = json.loads(update_poetry_declarations(content, changes))

    assert result["result"]["applied"] == [False, True]


def test_keeps_crlf_line_endings():
    content = "[tool.poetry.dependencies]\r\nfoo = \"^1\"\r\nbar = \"^1\"\r\n"

    new, _ = edit(content, "foo", "dependencies", "^1", "^2")

    assert new == content.replace("foo = \"^1\"", "foo = \"^2\"")


def test_without_a_group_searches_every_table():
    content = (
        "[project]\ndependencies = []\n\n"
        "[dependency-groups]\nlint = [\"ruff>=0.4\"]\n"
    )

    new, applied = edit(content, "ruff", None, ">=0.4", ">=0.5")

    assert applied
    assert new == content.replace(">=0.4", ">=0.5")


def test_falls_back_to_any_extras_in_the_group():
    content = (
        "[project.optional-dependencies]\n"
        "docs = [\"frequenz-repo-config[lib]==0.13.6\"]\n"
        "test = [\"frequenz-repo-config[extra-lint]==0.13.6\"]\n"
    )

    new, applied = edit(
        content, "frequenz-repo-config", "test", "==0.13.6", "==0.14.0",
        extras=["lib"],
    )

    assert applied
    assert new == content.replace(
        "[extra-lint]==0.13.6", "[extra-lint]==0.14.0"
    )
