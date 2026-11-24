import hashin
import json
import plette
import ssl
import traceback
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import urlopen
from poetry.factory import Factory


def get_dependency_hash(dependency_name, dependency_version, algorithm,
                        index_url=hashin.DEFAULT_INDEX_URL):
    try:
        options = {}
        package_data = package_data_under_index_path(
            dependency_name, index_url
        )
        if package_data is not None:
            options["lookup_memory"] = {dependency_name: package_data}

        hashes = hashin.get_package_hashes(
            dependency_name,
            version=dependency_version,
            algorithm=algorithm,
            index_url=index_url,
            **options
        )
        return json.dumps({"result": hashes["hashes"]})
    except hashin.PackageNotFoundError as e:
        return json.dumps({
            "error": repr(e),
            "error_class:": e.__class__.__name__,
            "trace:": ''.join(traceback.format_stack())
        })
    except (URLError, ssl.SSLError) as e:
        # Handle SSL certificate verification errors
        error_msg = str(e)
        if "CERTIFICATE_VERIFY_FAILED" in error_msg:
            return json.dumps({
                "error": "CERTIFICATE_VERIFY_FAILED: " + error_msg,
                "error_class:": e.__class__.__name__,
                "trace:": ''.join(traceback.format_stack())
            })
        # Re-raise if it's not a certificate verification error
        raise


def package_data_under_index_path(dependency_name, index_url):
    """Fetch the package's JSON from an index that is served under a path.

    hashin requests urljoin(index_url, "/pypi/<name>/json"), which drops the
    path of an index such as .../api/pypi/<repo>/simple. Try the URL that keeps
    the path first. Return None for an index at the host root, or when that
    URL does not answer with package JSON, so hashin's own URL is used.
    """
    parts = urlsplit(index_url)
    path = parts.path.rstrip("/")
    if path.endswith("/simple"):
        path = path[:-len("/simple")]
    if not path:
        return None

    url = urlunsplit((
        parts.scheme, parts.netloc,
        "%s/pypi/%s/json" % (path, dependency_name), "", ""
    ))
    try:
        with urlopen(url) as response:
            data = json.loads(response.read())
    except (HTTPError, ValueError):
        return None

    if not isinstance(data, dict) or not {"info", "releases"} <= data.keys():
        return None
    return data


def get_pipfile_hash(directory):
    with open(directory + '/Pipfile') as f:
        pipfile = plette.Pipfile.load(f)

    return json.dumps({"result": pipfile.get_hash().value})


def get_pyproject_hash(directory):
    p = Factory().create_poetry(directory)

    return json.dumps({"result": p.locker._get_content_hash()})
