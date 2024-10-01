This document outlines a standardized policy for when Dependabot will cease guaranteeing support for old versions of package managers and languages, and for when it will add support for new versions. "Cease guaranteeing support" is intentionally distinct from "deprecating support", because just because something's not supported, doesn't necessarily mean that we need to "rip out support immediately". Instead, it means more like, "if supporting this becomes a problem, we won't fix it".

These principles will need to be weighed against the unique circumstances, but without principles, we won't ever be able to make consistent decisions.
**General support principles**

We should try to align with the ideas of [SemVer2](https://semver.org/spec/v2.0.0.html), but we can’t guarantee everything will follow that.

* Support compatibility with major versions within 1 quarter  
  * Rationale: major versions will (presumably) have breaking updates, and users will follow them.   
* New features, e.g. a new lockfile type - Support within 2-4 quarters  
  * Rationale: This allows time for users to transition to using it. Not jumping on it immediately will also let the community gauge adoption so we don’t waste time on features nobody uses.
    * Exception: if it’s a **breaking** change that forces users to use the new thing - support that within 1 quarter (if it’s Semver, that should be a major version - but 🤷)  

**Deprecation principles**

* Once a version is deprecated by upstream, we do not guarantee to support it with additional bugfixes. However, typically we delay removing existing support for that version for a minimum of 3-6 months after upstream deprecates it.

[!NOTE]  
"Cease guaranteeing support" is intentionally distinct from "removing support"... even though a version may be deprecated, we may leave it around in the code for a bit to give folks more time to transition. We won't provide additional bugfixes, but if a community member steps up to provide a bugfix during that time, we will likely merge it. However, once leaving support in the code increases our maintenance costs / decreases our code velocity, then we will remove it.
 
We will publish deprecation notices within the GitHub Changelog, and where possible, we will send warnings to users about using versions targeted for deprecation within Dependabot.
  * Rationale: if it’s EOL by the maintainers, we shouldn’t need to keep supporting it either.  But also, unless it’s actively doing harm, there is probably not a rush.

**New package managers**

* We need to treat these like new ecosystems and be cautious about supporting without careful consideration, given the ongoing maintenance costs associated. See [CONTRIBUTING](CONTRIBUTING.md#contributing-new-ecosystems) for more details.
