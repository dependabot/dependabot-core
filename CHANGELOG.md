## v0.214.0, 30 November 2022

- Yarn Berry: Make a best effort to preserve file permissions (@pavera) [#6141](https://github.com/dependabot/dependabot-core/pull/6141)
- Check if existing python requirement is satisfied before modifying (@pavera) [#6237](https://github.com/dependabot/dependabot-core/pull/6237)
- Prevent `NoMethodError` when captures are missing (@landongrindheim) [#6227](https://github.com/dependabot/dependabot-core/pull/6227)
- Respect existing precision of base docker images (@deivid-rodriguez) [#6170](https://github.com/dependabot/dependabot-core/pull/6170)
- test: add test for private registry module with dir suffix (@stigok) [#6137](https://github.com/dependabot/dependabot-core/pull/6137)
- Improve Bundler configuration (@deivid-rodriguez) [#6069](https://github.com/dependabot/dependabot-core/pull/6069)
- Fix dependabot not updating gemspec dependencies loaded dynamically from other gemspecs (@deivid-rodriguez) [#6188](https://github.com/dependabot/dependabot-core/pull/6188)
- Use git to fill in gemspec files (@deivid-rodriguez) [#6199](https://github.com/dependabot/dependabot-core/pull/6199)
- Remove hardcoded master branch (@deivid-rodriguez) [#6149](https://github.com/dependabot/dependabot-core/pull/6149)
- Honor new dir selection logic in Github Actions error messages (@deivid-rodriguez) [#6192](https://github.com/dependabot/dependabot-core/pull/6192)
- Mention BitBucket is supported by dependabot-script (@jeffwidman) [#6198](https://github.com/dependabot/dependabot-core/pull/6198)
- Use only python major.minor version (@pavera) [#6195](https://github.com/dependabot/dependabot-core/pull/6195)
- Fix inconsistent docker updates with `-` suffixed images (@deivid-rodriguez) [#6173](https://github.com/dependabot/dependabot-core/pull/6173)
- Bump minimatch from 3.0.4 to 3.1.2 in /npm_and_yarn/helpers/test/npm6/fixtures/conflicting-dependency-parser/deeply-nested [#6162](https://github.com/dependabot/dependabot-core/pull/6162)
- Add a spec to cover custom dir given to actions (@deivid-rodriguez) [#6190](https://github.com/dependabot/dependabot-core/pull/6190)
- Respect custom directory for actions updates (@deivid-rodriguez) [#6189](https://github.com/dependabot/dependabot-core/pull/6189)
- Allow cargo versions with hypens in build identifiers (@deivid-rodriguez) [#6183](https://github.com/dependabot/dependabot-core/pull/6183)
- Add security update support for Github Actions (@deivid-rodriguez) [#6071](https://github.com/dependabot/dependabot-core/pull/6071)
- Refactor some common logic across ecosystems (@deivid-rodriguez) [#6164](https://github.com/dependabot/dependabot-core/pull/6164)
- Use pre-built python as much as possible. (@pavera) [#6079](https://github.com/dependabot/dependabot-core/pull/6079)
- Yarn Berry: Use -R for yarn up (@pavera) [#6167](https://github.com/dependabot/dependabot-core/pull/6167)
- Yarn Berry: Adding a peer dependency checker (@pavera) [#6077](https://github.com/dependabot/dependabot-core/pull/6077)
- Add missing Python versions (@ulgens) [#6089](https://github.com/dependabot/dependabot-core/pull/6089)
- Bump loader-utils from 1.4.1 to 1.4.2 in /npm_and_yarn/helpers [#6156](https://github.com/dependabot/dependabot-core/pull/6156)
- Create a permanent root Gemfile (@deivid-rodriguez) [#6159](https://github.com/dependabot/dependabot-core/pull/6159)
- Adding yarn berry smoke test (@pavera) [#6154](https://github.com/dependabot/dependabot-core/pull/6154)
- Fix updating GitHub actions to major tags that are branches (@deivid-rodriguez) [#5963](https://github.com/dependabot/dependabot-core/pull/5963)
- Private hex repo support (@sorentwo) [#5043](https://github.com/dependabot/dependabot-core/pull/5043)
- Make specs time zone independent (@deivid-rodriguez) [#6135](https://github.com/dependabot/dependabot-core/pull/6135)
- Consider precision when finding latest action (@deivid-rodriguez) [#6102](https://github.com/dependabot/dependabot-core/pull/6102)
- Remove `faraday-retry` warning (@deivid-rodriguez) [#6114](https://github.com/dependabot/dependabot-core/pull/6114)
- Fix spaces in uri (@AlekhyaYalla) [#5656](https://github.com/dependabot/dependabot-core/pull/5656)
- Fix multiple constraint Poetry dependencies getting bad updates (@deivid-rodriguez) [#6074](https://github.com/dependabot/dependabot-core/pull/6074)
- Don't leak pipenv warnings into manifest files (@deivid-rodriguez) [#6103](https://github.com/dependabot/dependabot-core/pull/6103)
- Fix GitHub actions updater crashing and cloning the wrong repository (@deivid-rodriguez) [#6052](https://github.com/dependabot/dependabot-core/pull/6052)
- Update SECURITY.md (@maclarel) [#6093](https://github.com/dependabot/dependabot-core/pull/6093)
- Bump friendsofphp/php-cs-fixer from 3.12.0 to 3.13.0 in /composer/helpers/v2 [#6063](https://github.com/dependabot/dependabot-core/pull/6063)
- Bump eslint from 8.26.0 to 8.27.0 in /npm_and_yarn/helpers [#6061](https://github.com/dependabot/dependabot-core/pull/6061)
- Bump phpstan/phpstan from 1.8.11 to 1.9.1 in /composer/helpers/v2 [#6062](https://github.com/dependabot/dependabot-core/pull/6062)
- Bump phpstan/phpstan from 1.8.11 to 1.9.1 in /composer/helpers/v1 [#6064](https://github.com/dependabot/dependabot-core/pull/6064)
- Update parallel_tests requirement from ~> 3.13.0 to ~> 4.0.0 in /common [#6059](https://github.com/dependabot/dependabot-core/pull/6059)
- Yarn Berry: Subdependency fixes (@pavera) [#6040](https://github.com/dependabot/dependabot-core/pull/6040)
- Don't fail if dependency with unknown vcs has local replacement (@zioyero) [#5983](https://github.com/dependabot/dependabot-core/pull/5983)
- Upgrade Bundler to 2.3.25 (@Bo98) [#6042](https://github.com/dependabot/dependabot-core/pull/6042)
- nuget: keep version build identifiers out of manifests (@jakecoffman) [#6034](https://github.com/dependabot/dependabot-core/pull/6034)
- Fix some PEP 621 projects not getting upgrades (@deivid-rodriguez) [#6032](https://github.com/dependabot/dependabot-core/pull/6032)
- Fix accidental downgrades in Bundler PRs (@deivid-rodriguez) [#6030](https://github.com/dependabot/dependabot-core/pull/6030)
- Yarn Berry: Use appropriate mode for yarn version and repo state (@pavera) [#6017](https://github.com/dependabot/dependabot-core/pull/6017)
- Removes `YarnLockfileParser` (@bdragon) [#6016](https://github.com/dependabot/dependabot-core/pull/6016)
- Yarn Private Registry Support (@Nishnha) [#5883](https://github.com/dependabot/dependabot-core/pull/5883)
- Yarn Berry: run git lfs pull before running yarn (@jtbandes) [#5833](https://github.com/dependabot/dependabot-core/pull/5833)
- fix hex native helpers: v2.0.0 removed Hex.Version.InvalidRequirementError (@jakecoffman) [#6006](https://github.com/dependabot/dependabot-core/pull/6006)

## v0.213.0, 31 October 2022

- prevent failing to create a PR due to metadata gathering errors [#5980](https://github.com/dependabot/dependabot-core/pull/5980)
- Bump Node.js in bug report description field (@HonkingGoose) [#5984](https://github.com/dependabot/dependabot-core/pull/5984)
- Allow file fetchers to opt into loading git submodules [#5982](https://github.com/dependabot/dependabot-core/pull/5982)
- Centralize pyenv install logic [#5985](https://github.com/dependabot/dependabot-core/pull/5985)
- prevent trying to get a commit that can't exist [#5981](https://github.com/dependabot/dependabot-core/pull/5981)
- Remove Current User From List of Default Reviewer (@Kimor-hello) [#5968](https://github.com/dependabot/dependabot-core/pull/5968)
- Bump @npmcli/arborist from 5.6.2 to 6.0.0 in /npm_and_yarn/helpers [#5955](https://github.com/dependabot/dependabot-core/pull/5955)
- Update rubocop requirement from ~> 1.36.0 to ~> 1.37.1 in /common [#5959](https://github.com/dependabot/dependabot-core/pull/5959)
- Regenerate `updater/Gemfile.lock` [#5858](https://github.com/dependabot/dependabot-core/pull/5858)
- Keep updater lockfile in sync with subgem changes [#5972](https://github.com/dependabot/dependabot-core/pull/5972)
- Add Dependency Review workflow [#5973](https://github.com/dependabot/dependabot-core/pull/5973)
- Yarn Berry: Fully update cache and include .pnp.cjs in PR [#5964](https://github.com/dependabot/dependabot-core/pull/5964)
- Actually consider development dependencies (v2) [#5971](https://github.com/dependabot/dependabot-core/pull/5971)
- Actually consider development dependencies [#5969](https://github.com/dependabot/dependabot-core/pull/5969)
- Fix crashes on Python libraries using multiple manifests [#5965](https://github.com/dependabot/dependabot-core/pull/5965)
- Fix rubocop redundant freeze warnings [#5468](https://github.com/dependabot/dependabot-core/pull/5468)
- Don't repeat dependency names in PR title [#5915](https://github.com/dependabot/dependabot-core/pull/5915)
- fix race and updating local mounted repositories [#5937](https://github.com/dependabot/dependabot-core/pull/5937)
- Initial work on standard Python support [#5661](https://github.com/dependabot/dependabot-core/pull/5661)
- Only call pip compile once (@jerbob92) [#5905](https://github.com/dependabot/dependabot-core/pull/5905)
- Bump rubocop from 1.36.0 to 1.37.1 in /updater [#5960](https://github.com/dependabot/dependabot-core/pull/5960)
- Bump licensed from 3.7.4 to 3.7.5 in /updater [#5957](https://github.com/dependabot/dependabot-core/pull/5957)
- Update octokit requirement from >= 4.6, < 6.0 to >= 4.6, < 7.0 in /common [#5954](https://github.com/dependabot/dependabot-core/pull/5954)
- Make dry-run script twice as fast [#5950](https://github.com/dependabot/dependabot-core/pull/5950)
- Bump collection from 1.16.0 to 1.17.0 in /pub/helpers [#5898](https://github.com/dependabot/dependabot-core/pull/5898)
- Bump eslint from 8.25.0 to 8.26.0 in /npm_and_yarn/helpers [#5953](https://github.com/dependabot/dependabot-core/pull/5953)
- Update pip requirement from <22.2.3,>=21.3.1 to >=21.3.1,<22.4.0 in /python/helpers [#5893](https://github.com/dependabot/dependabot-core/pull/5893)
- build(deps): bump terraform from 1.3.2 to 1.3.3 (@HorizonNet) [#5952](https://github.com/dependabot/dependabot-core/pull/5952)
- No public url call when public registry is disabled [#5948](https://github.com/dependabot/dependabot-core/pull/5948)
- fix calling npm.org when there's no npmrc with replaces-base [#5928](https://github.com/dependabot/dependabot-core/pull/5928)
- Never change version precision of actions chosen by users [#5891](https://github.com/dependabot/dependabot-core/pull/5891)
- Bump nokogiri from 1.13.8 to 1.13.9 in /updater [#5936](https://github.com/dependabot/dependabot-core/pull/5936)
- Fix crash when updating git dependencies [#5934](https://github.com/dependabot/dependabot-core/pull/5934)
- Fix error when parsing Gitlab changelogs [#5929](https://github.com/dependabot/dependabot-core/pull/5929)
- Fix crash when updating Python libraries with multiple manifest types [#5932](https://github.com/dependabot/dependabot-core/pull/5932)
- Fix updating to tags with a branch with same name [#5918](https://github.com/dependabot/dependabot-core/pull/5918)
- Batch some PRs updating dependencies [#5942](https://github.com/dependabot/dependabot-core/pull/5942)
- Maven: fix forgetting repositories seen in earlier POMs [#5931](https://github.com/dependabot/dependabot-core/pull/5931)
- Yarn Berry: Fixes subdependency security updates [#5930](https://github.com/dependabot/dependabot-core/pull/5930)
- Bump phpstan/phpstan from 1.8.8 to 1.8.10 in /composer/helpers/v1 [#5910](https://github.com/dependabot/dependabot-core/pull/5910)
- Bump friendsofphp/php-cs-fixer from 3.11.0 to 3.12.0 in /composer/helpers/v2 [#5895](https://github.com/dependabot/dependabot-core/pull/5895)
- Install composer in a way that does not use `COPY --from` [#5904](https://github.com/dependabot/dependabot-core/pull/5904)
- Fall back to PR title if original PR head commit is missing [#5913](https://github.com/dependabot/dependabot-core/pull/5913)
- Maven: implement parent snapshot lookup [#5924](https://github.com/dependabot/dependabot-core/pull/5924)
- Fixed disabledPackageSources for nuget.org [#5874](https://github.com/dependabot/dependabot-core/pull/5874)
- maven: implement replaces-base to avoid calling central [#5908](https://github.com/dependabot/dependabot-core/pull/5908)
- Fix commitlint message style detection [#5744](https://github.com/dependabot/dependabot-core/pull/5744)
- Fixing PR failures if pypi.org unavailable [#5876](https://github.com/dependabot/dependabot-core/pull/5876)
- Fix dependabot incorrectly downgrading docker versions [#5886](https://github.com/dependabot/dependabot-core/pull/5886)
- fix version_finder not preferring private registry [#5907](https://github.com/dependabot/dependabot-core/pull/5907)
- Remove CI hack much less needed now [#5906](https://github.com/dependabot/dependabot-core/pull/5906)
- add Maven credential metadata to the URLs it searches for POM files [#5884](https://github.com/dependabot/dependabot-core/pull/5884)
- Revert lockfile-only changes [#5901](https://github.com/dependabot/dependabot-core/pull/5901)
- Detect dependencies in Gradle included builds (@gabrielfeo) [#5028](https://github.com/dependabot/dependabot-core/pull/5028)
- Make `script/dependabot --help` actually work [#5881](https://github.com/dependabot/dependabot-core/pull/5881)
- Fix `lockfile-only` versioning strategy not creating some updates that are expected [#5581](https://github.com/dependabot/dependabot-core/pull/5581)
- Fix Maven inability to overwrite repository urls by ID [#5878](https://github.com/dependabot/dependabot-core/pull/5878)
- Revert "Bump activesupport from 6.1.4.4 to 7.0.4 in /updater" [#5882](https://github.com/dependabot/dependabot-core/pull/5882)
- Bump activesupport from 6.1.4.4 to 7.0.4 in /updater [#5704](https://github.com/dependabot/dependabot-core/pull/5704)
- [npm] Flag indirect transitive updates to be ignored by the FileUpdater [#5873](https://github.com/dependabot/dependabot-core/pull/5873)
- [npm] Randomize advisory id to avoid cache collisions across tests [#5875](https://github.com/dependabot/dependabot-core/pull/5875)
- maven: stop querying repositories once one returns a result [#5872](https://github.com/dependabot/dependabot-core/pull/5872)
- Yarn Berry: Ensure registry config is respected [#5863](https://github.com/dependabot/dependabot-core/pull/5863)
- raise when a path dependency is absolute [#5869](https://github.com/dependabot/dependabot-core/pull/5869)
- Update `.dockerignore` [#5585](https://github.com/dependabot/dependabot-core/pull/5585)
- Bump phpstan/phpstan from 1.8.6 to 1.8.8 in /composer/helpers/v2 [#5860](https://github.com/dependabot/dependabot-core/pull/5860)
- Make quotes around Yarn private registry sources optional [#5844](https://github.com/dependabot/dependabot-core/pull/5844)
- Fix typos [#5859](https://github.com/dependabot/dependabot-core/pull/5859)
- swap history file from `byebug` to new `debug` gem [#5855](https://github.com/dependabot/dependabot-core/pull/5855)
- [npm] fix to preserve all_versions metadata from the lockfile [#5846](https://github.com/dependabot/dependabot-core/pull/5846)
- handle path="" correctly in Cargo.toml [#5866](https://github.com/dependabot/dependabot-core/pull/5866)
- allow interactive debugging in the CLI [#5763](https://github.com/dependabot/dependabot-core/pull/5763)
- Update faraday requirement from = 2.5.2 to = 2.6.0 in /common [#5851](https://github.com/dependabot/dependabot-core/pull/5851)
- Add support for Python 3.10.7 and 3.[7-9].14 (@Kurt-von-Laven) [#5769](https://github.com/dependabot/dependabot-core/pull/5769)
- build(deps): bump terraform from 1.3.0 to 1.3.2 (@HorizonNet) [#5857](https://github.com/dependabot/dependabot-core/pull/5857)
- Update pip-tools requirement from <6.8.1,>=6.4.0 to >=6.4.0,<6.9.1 in /python/helpers [#5850](https://github.com/dependabot/dependabot-core/pull/5850)
- Bump http from 4.4.1 to 5.1.0 in /updater [#5701](https://github.com/dependabot/dependabot-core/pull/5701)
- Bump jest from 28.1.3 to 29.1.2 in /npm_and_yarn/helpers [#5821](https://github.com/dependabot/dependabot-core/pull/5821)
- Bump semver from 7.3.7 to 7.3.8 in /npm_and_yarn/helpers [#5848](https://github.com/dependabot/dependabot-core/pull/5848)
- Bump licensed from 3.7.3 to 3.7.4 in /updater [#5849](https://github.com/dependabot/dependabot-core/pull/5849)
- feat: Add support for `workspace.dependencies` in `cargo` 1.64.0+ (@poliorcetics) [#5794](https://github.com/dependabot/dependabot-core/pull/5794)
- Update debug requirement from ~> 1.0.0 to ~> 1.6.2 in /updater [#5853](https://github.com/dependabot/dependabot-core/pull/5853)
- Bump eslint from 8.24.0 to 8.25.0 in /npm_and_yarn/helpers [#5852](https://github.com/dependabot/dependabot-core/pull/5852)
- Bump phpstan/phpstan from 1.8.6 to 1.8.8 in /composer/helpers/v1 [#5854](https://github.com/dependabot/dependabot-core/pull/5854)
- Fix typo [#5847](https://github.com/dependabot/dependabot-core/pull/5847)
- Bump Ruby to 3.1 [#5447](https://github.com/dependabot/dependabot-core/pull/5447)
- [npm] Consider all installed versions when checking if a dependency is still vulnerable [#5801](https://github.com/dependabot/dependabot-core/pull/5801)
- use configured global registry for library lookup [#5840](https://github.com/dependabot/dependabot-core/pull/5840)
- allow updating at a commit, for testing [#5843](https://github.com/dependabot/dependabot-core/pull/5843)
- Fix Dependabot removes double backslashes in maven plugin configurations (@mallowlabs) [#5835](https://github.com/dependabot/dependabot-core/pull/5835)
- Stop disabling new `poetry` installer [#5838](https://github.com/dependabot/dependabot-core/pull/5838)
- Bump Rubygems to `3.3.22` [#5823](https://github.com/dependabot/dependabot-core/pull/5823)
- Yarn Berry: Private registry support [#5831](https://github.com/dependabot/dependabot-core/pull/5831)
- Consider all dependency versions in Job.vulnerable? [#5837](https://github.com/dependabot/dependabot-core/pull/5837)
- Yarn Berry: Ensure multiple requirements are parsed correctly [#5839](https://github.com/dependabot/dependabot-core/pull/5839)
- Add support for helm files. (@brendandburns) [#5738](https://github.com/dependabot/dependabot-core/pull/5738)
- Update `v1/composer.lock` using `composer1 update` [#5717](https://github.com/dependabot/dependabot-core/pull/5717)
- Decouple Bundler versions [#5513](https://github.com/dependabot/dependabot-core/pull/5513)
- Upgrade Bundler to 2.3.22 [#5509](https://github.com/dependabot/dependabot-core/pull/5509)
- Add support for Python 3.10.6 (@Kurt-von-Laven) [#5780](https://github.com/dependabot/dependabot-core/pull/5780)
- Yarn Berry: Prevent sub-package dependencies being added to root workspace [#5829](https://github.com/dependabot/dependabot-core/pull/5829)
- [npm] Preserve requirement source when updating transtive dep parents [#5816](https://github.com/dependabot/dependabot-core/pull/5816)
- [npm] Allow updates with both top level and sub dependencies [#5822](https://github.com/dependabot/dependabot-core/pull/5822)
- Yarn Berry: Run commands in `update-lockfile` mode [#5827](https://github.com/dependabot/dependabot-core/pull/5827)
- Update parallel_tests requirement from ~> 3.12.0 to ~> 3.13.0 in /common [#5791](https://github.com/dependabot/dependabot-core/pull/5791)
- [npm] Reject audits which don't have a fix we can apply [#5815](https://github.com/dependabot/dependabot-core/pull/5815)
- Update all versions of the same private module in single terraform file (@szemek) [#5786](https://github.com/dependabot/dependabot-core/pull/5786)
- Ensure always_clone is enabled for yarn_berry during file_fetching [#5817](https://github.com/dependabot/dependabot-core/pull/5817)
- Bump phpstan/phpstan from 1.8.5 to 1.8.6 in /composer/helpers/v2 [#5792](https://github.com/dependabot/dependabot-core/pull/5792)
- Bump phpstan/phpstan from 1.8.5 to 1.8.6 in /composer/helpers/v1 [#5793](https://github.com/dependabot/dependabot-core/pull/5793)
- Bump eslint from 8.23.1 to 8.24.0 in /npm_and_yarn/helpers [#5790](https://github.com/dependabot/dependabot-core/pull/5790)
- add dependabot CLI dev container [#5813](https://github.com/dependabot/dependabot-core/pull/5813)
- smoke test npm removed dependencies [#5808](https://github.com/dependabot/dependabot-core/pull/5808)
- Set custom CA file path for yarn berry [#5783](https://github.com/dependabot/dependabot-core/pull/5783)
- [npm] fix failure to attempt parent update if unfixed transitive update is available [#5799](https://github.com/dependabot/dependabot-core/pull/5799)
- Fix syntax error in Actions workflow file [#5805](https://github.com/dependabot/dependabot-core/pull/5805)
- Update smoke test to download CLI from `dependabot/cli` repo [#5803](https://github.com/dependabot/dependabot-core/pull/5803)
- Fix typo in README (promted -> prompted) (@szemek) [#5802](https://github.com/dependabot/dependabot-core/pull/5802)
- remove :npm_transitive_security_updates flag [#5788](https://github.com/dependabot/dependabot-core/pull/5788)
- [Gradle] Handle plugin version variables without string interpolation (@Flexicon) [#5381](https://github.com/dependabot/dependabot-core/pull/5381)
- [npm] Only shortcut search when non-vuln version of advisory dep is found [#5796](https://github.com/dependabot/dependabot-core/pull/5796)
- Terraform 1.3.0 [#5782](https://github.com/dependabot/dependabot-core/pull/5782)
- Skip cron run of CodeQL in forks [#5784](https://github.com/dependabot/dependabot-core/pull/5784)
- [npm] Only return a chain if a node matches a vulnerable version [#5785](https://github.com/dependabot/dependabot-core/pull/5785)
- bundler: optimize gemfile parsing (@skipkayhil) [#4059](https://github.com/dependabot/dependabot-core/pull/4059)
- Initial yarn berry support [#5660](https://github.com/dependabot/dependabot-core/pull/5660)
- Fixing issue with nuget devDependency support (@mwaddell) [#4774](https://github.com/dependabot/dependabot-core/pull/4774)
- Bump commonmarker from 0.23.5 to 0.23.6 in /updater [#5773](https://github.com/dependabot/dependabot-core/pull/5773)
- Bump @npmcli/arborist from 5.6.1 to 5.6.2 in /npm_and_yarn/helpers [#5747](https://github.com/dependabot/dependabot-core/pull/5747)
- Update poetry requirement from <=1.2.0,>=1.1.15 to >=1.1.15,<1.3.0 in /python/helpers [#5746](https://github.com/dependabot/dependabot-core/pull/5746)
- Improve PR message for removed dependencies [#5770](https://github.com/dependabot/dependabot-core/pull/5770)
- build(deps): bump NPM from 8.18.0 to 8.19.2 (@THETCR) [#5754](https://github.com/dependabot/dependabot-core/pull/5754)
- prevent forks from trying and failing to deploy to GHCR [#5768](https://github.com/dependabot/dependabot-core/pull/5768)
- Sanitize metadata links on all platforms [#5739](https://github.com/dependabot/dependabot-core/pull/5739)
- Fixes for transitive dependency vulnerabilities without a top level dependency update [#5762](https://github.com/dependabot/dependabot-core/pull/5762)
- Experiments not Experiment [#5760](https://github.com/dependabot/dependabot-core/pull/5760)
- More descriptive PR message when multiple dependencies are fixed in a security update [#5595](https://github.com/dependabot/dependabot-core/pull/5595)
- Add new interface to register experiments [#5755](https://github.com/dependabot/dependabot-core/pull/5755)
- [pub] Log the Dart / Flutter SDK version selected (@sigurdm) [#5748](https://github.com/dependabot/dependabot-core/pull/5748)
- Run CI and smoke tests on stacked PRs [#5752](https://github.com/dependabot/dependabot-core/pull/5752)
- Fix multiple Python requirements separated by whitespace [#5735](https://github.com/dependabot/dependabot-core/pull/5735)
- Allow updating Java images with "update releases" [#5734](https://github.com/dependabot/dependabot-core/pull/5734)
- Support `bump_versions_if_necessary` versioning strategy in python [#5605](https://github.com/dependabot/dependabot-core/pull/5605)
- Sanitize mentions for merge requests in Gitlab (@andrcuns) [#3437](https://github.com/dependabot/dependabot-core/pull/3437)
- add a date tag to the docker image when merged [#5736](https://github.com/dependabot/dependabot-core/pull/5736)
- Make `script/debug` a simple wrapper over the CLI [#5733](https://github.com/dependabot/dependabot-core/pull/5733)
- Use `"latest"` for ESLint `ecmaVersion` [#5715](https://github.com/dependabot/dependabot-core/pull/5715)
- Fix URIs logged by dry-run [#5732](https://github.com/dependabot/dependabot-core/pull/5732)
- Bump webmock from 3.17.1 to 3.18.1 in /updater [#5700](https://github.com/dependabot/dependabot-core/pull/5700)
- Add composer fields to silence PHPStan [#5716](https://github.com/dependabot/dependabot-core/pull/5716)
- Add max length option to BranchNamer (@TomNaessens) [#5338](https://github.com/dependabot/dependabot-core/pull/5338)
- Bump jason from 1.3.0 to 1.4.0 in /hex/helpers [#5699](https://github.com/dependabot/dependabot-core/pull/5699)
- Fix fetching bug for requirements.in files (@stulle123) [#5580](https://github.com/dependabot/dependabot-core/pull/5580)
- Relax the composer pin to make it less confusing [#5714](https://github.com/dependabot/dependabot-core/pull/5714)
- Fix `PHP-CS-Fixer` deprecation warnings [#5713](https://github.com/dependabot/dependabot-core/pull/5713)
- Revert "disable branch release workflow for forks" [#5711](https://github.com/dependabot/dependabot-core/pull/5711)
- disable branch release workflow for forks [#5709](https://github.com/dependabot/dependabot-core/pull/5709)
- Bump rubocop-performance from 1.14.3 to 1.15.0 in /updater [#5703](https://github.com/dependabot/dependabot-core/pull/5703)
- Bump rubocop from 1.33.0 to 1.36.0 in /updater [#5702](https://github.com/dependabot/dependabot-core/pull/5702)
- Rename `phpstan.neon` -> `phpstan.dist.neon` [#5692](https://github.com/dependabot/dependabot-core/pull/5692)
- Fix typo [#5696](https://github.com/dependabot/dependabot-core/pull/5696)
- Fix typo (@HonkingGoose) [#5705](https://github.com/dependabot/dependabot-core/pull/5705)
- Rename `.php_cs` -> `.php-cs-fixer.dist.php` [#5691](https://github.com/dependabot/dependabot-core/pull/5691)
- Watch the new `updater/Gemfile` [#5697](https://github.com/dependabot/dependabot-core/pull/5697)
- Handle removed dependencies in existing PRs [#5673](https://github.com/dependabot/dependabot-core/pull/5673)
- Bump friendsofphp/php-cs-fixer from 3.9.3 to 3.11.0 in /composer/helpers/v2 [#5689](https://github.com/dependabot/dependabot-core/pull/5689)
- build(deps-dev): bump phpstan/phpstan from 1.7.15 to 1.8.5 in /composer/helpers/v1 [#5651](https://github.com/dependabot/dependabot-core/pull/5651)
- build(deps-dev): bump phpstan/phpstan from 1.8.1 to 1.8.5 in /composer/helpers/v2 [#5652](https://github.com/dependabot/dependabot-core/pull/5652)
- Update debase-ruby_core_source requirement from = 0.10.16 to = 0.10.17 in /common [#5677](https://github.com/dependabot/dependabot-core/pull/5677)
- fix Poetry not using system git [#5688](https://github.com/dependabot/dependabot-core/pull/5688)
- build(deps): bump @npmcli/arborist from 5.6.0 to 5.6.1 in /npm_and_yarn/helpers [#5629](https://github.com/dependabot/dependabot-core/pull/5629)
- Increase docker registry client timeout [#5674](https://github.com/dependabot/dependabot-core/pull/5674)
- deploy from a fork using a workflow [#5668](https://github.com/dependabot/dependabot-core/pull/5668)
- Bump eslint from 8.22.0 to 8.23.1 in /npm_and_yarn/helpers [#5679](https://github.com/dependabot/dependabot-core/pull/5679)
- python/helpers/build: fix a pip warning related to pipfile installation (@SpecLad) [#5587](https://github.com/dependabot/dependabot-core/pull/5587)
- Update file size to 500 kilobytes (@stulle123) [#5596](https://github.com/dependabot/dependabot-core/pull/5596)
- build(deps): bump terraform from 1.2.8 to 1.2.9 (@HorizonNet) [#5675](https://github.com/dependabot/dependabot-core/pull/5675)
- Update rubocop-performance requirement from ~> 1.14.2 to ~> 1.15.0 in /common [#5680](https://github.com/dependabot/dependabot-core/pull/5680)
- Fix typo: spwans -> spawns [#5681](https://github.com/dependabot/dependabot-core/pull/5681)
- Reword comment & fix typo [#5682](https://github.com/dependabot/dependabot-core/pull/5682)
- Test #conficting_dependencies with a locking parent dependabot fixture [#5672](https://github.com/dependabot/dependabot-core/pull/5672)
- Include removed dependency flag when creating a pull request [#5671](https://github.com/dependabot/dependabot-core/pull/5671)
- Cleanup updater specs output [#5666](https://github.com/dependabot/dependabot-core/pull/5666)
- [npm] Add additional logging to VulnerabilityAuditor [#5662](https://github.com/dependabot/dependabot-core/pull/5662)
- fix smoke tests from forks by using public sources [#5665](https://github.com/dependabot/dependabot-core/pull/5665)
- Speed up dealing with non-reachable git repos [#5658](https://github.com/dependabot/dependabot-core/pull/5658)
- Fix incomplete clean up of odd python requirements [#5647](https://github.com/dependabot/dependabot-core/pull/5647)
- Run `rspec` with `--profile` flag by default in Python [#5607](https://github.com/dependabot/dependabot-core/pull/5607)
- Propagate author details when initializing PullRequestUpdater for Azure. (@JManou) [#5604](https://github.com/dependabot/dependabot-core/pull/5604)
- Fix updater specs on M1 [#5657](https://github.com/dependabot/dependabot-core/pull/5657)
- fix tagged push overwriting previous tags [#5649](https://github.com/dependabot/dependabot-core/pull/5649)
- Add more helpful error messaging when a vulnerable dependency cannot be upgraded [#5645](https://github.com/dependabot/dependabot-core/pull/5645)
- deploy commits made after approval [#5650](https://github.com/dependabot/dependabot-core/pull/5650)
- To prevent dependabot-core from failing when the incorrect release tag is created for a release, adding a rescue statement [#5615](https://github.com/dependabot/dependabot-core/pull/5615)
- Adding code tags around any nwo#number text string [#5646](https://github.com/dependabot/dependabot-core/pull/5646)
- move devcontainer to allow debugging updater with the default devcontainer [#5648](https://github.com/dependabot/dependabot-core/pull/5648)
- Revert "Add more helpful error messaging when a vulnerable dependency cannot be upgraded" [#5613](https://github.com/dependabot/dependabot-core/pull/5613)

## v0.212.0, 6 September 2022

- prevent the push to main event from skipping [#5641](https://github.com/dependabot/dependabot-core/pull/5641)
- Fix path to python native helpers [#5617](https://github.com/dependabot/dependabot-core/pull/5617)
- push docker images after approval [#5640](https://github.com/dependabot/dependabot-core/pull/5640)
- branch naming for removed dependencies [#5623](https://github.com/dependabot/dependabot-core/pull/5623)
- Properly upgrade github actions pinned to specific commits [#5576](https://github.com/dependabot/dependabot-core/pull/5576)
- pull request message is always built, removing experiment [#5638](https://github.com/dependabot/dependabot-core/pull/5638)
- gradle depends on maven gem, so run gradle tests when maven changes [#5637](https://github.com/dependabot/dependabot-core/pull/5637)
- build(deps-dev): update parallel_tests requirement from ~> 3.11.1 to ~> 3.12.0 in /common [#5627](https://github.com/dependabot/dependabot-core/pull/5627)
- build(deps-dev): update rubocop requirement from ~> 1.35.1 to ~> 1.36.0 in /common [#5628](https://github.com/dependabot/dependabot-core/pull/5628)
- fix latest docker image not being pushed on merge to main [#5636](https://github.com/dependabot/dependabot-core/pull/5636)
- Add RuboCop Performance [#5586](https://github.com/dependabot/dependabot-core/pull/5586)
- Speedup rebuilding native helper changes [#5624](https://github.com/dependabot/dependabot-core/pull/5624)
- build(deps): bump poetry from 1.1.15 to 1.2.0 in /python/helpers [#5599](https://github.com/dependabot/dependabot-core/pull/5599)
- fix main failures saying there's no repository here [#5622](https://github.com/dependabot/dependabot-core/pull/5622)
- skip CI if no changes effect the ecosystem [#5620](https://github.com/dependabot/dependabot-core/pull/5620)
- only use GHCR for deploys [#5614](https://github.com/dependabot/dependabot-core/pull/5614)
- Enable new RuboCop cops [#5588](https://github.com/dependabot/dependabot-core/pull/5588)
- Configure RSpec to allow running `rspec --only-failures` [#5606](https://github.com/dependabot/dependabot-core/pull/5606)
- Revert "Add more helpful error messaging when a vulnerable dependency cannot be upgraded" [#5613](https://github.com/dependabot/dependabot-core/pull/5613)
- publish main branch images [#5610](https://github.com/dependabot/dependabot-core/pull/5610)
- build(deps): bump terraform from 1.2.3 to 1.2.8 (@gtirloni) [#5591](https://github.com/dependabot/dependabot-core/pull/5591)
- Add more helpful error messaging when a vulnerable dependency cannot be upgraded [#5542](https://github.com/dependabot/dependabot-core/pull/5542)
- Merge previously private updater code into core [#5608](https://github.com/dependabot/dependabot-core/pull/5608)
- Use correct label for tech debt form (@HonkingGoose) [#5602](https://github.com/dependabot/dependabot-core/pull/5602)
- Convert issue templates to issue forms (@HonkingGoose) [#5600](https://github.com/dependabot/dependabot-core/pull/5600)
- Dependabot Ltd -> GitHub Inc [#5592](https://github.com/dependabot/dependabot-core/pull/5592)
- Fix typo: `requiers` -> `requires` [#5583](https://github.com/dependabot/dependabot-core/pull/5583)
- build(deps): update faraday requirement from = 2.3.0 to = 2.5.2 in /common [#5535](https://github.com/dependabot/dependabot-core/pull/5535)

## v0.211.0, 23 August 2022

- Support for transitive dependency removal [#5549](https://github.com/dependabot/dependabot-core/pull/5549)
- build(deps): bump poetry from 1.1.14 to 1.1.15 in /python/helpers [#5578](https://github.com/dependabot/dependabot-core/pull/5578)
- Adding required checks in ci-release.yml [#5575](https://github.com/dependabot/dependabot-core/pull/5575)

## v0.210.0, 23 August 2022

- build(deps): bump nock from 13.2.8 to 13.2.9 in /npm_and_yarn/helpers [#5397](https://github.com/dependabot/dependabot-core/pull/5397)
- build(deps): bump NPM from 8.5.1 to 8.18.0 (@THETCR) [#5518](https://github.com/dependabot/dependabot-core/pull/5518)
- build(deps-dev): bump eslint from 8.21.0 to 8.22.0 in /npm_and_yarn/helpers [#5533](https://github.com/dependabot/dependabot-core/pull/5533)
- Fix file updater removing variants from docker tags [#5560](https://github.com/dependabot/dependabot-core/pull/5560)
- Update rubocop requirement from ~> 1.33.0 to ~> 1.35.1 in /common [#5564](https://github.com/dependabot/dependabot-core/pull/5564)
- Fix Bundler vendoring when a subdirectory is configured [#5567](https://github.com/dependabot/dependabot-core/pull/5567)
- Fix CI matrices [#5573](https://github.com/dependabot/dependabot-core/pull/5573)
- Split slow ecosystems across multiple CI jobs [#5568](https://github.com/dependabot/dependabot-core/pull/5568)
- Set the author details when updating an Azure pull request. (@JManou) [#5557](https://github.com/dependabot/dependabot-core/pull/5557)
- Bump @npmcli/arborist from 5.3.1 to 5.6.0 in /npm_and_yarn/helpers [#5563](https://github.com/dependabot/dependabot-core/pull/5563)
- Bump docker_registry2 to fix #3989 (@noorul) [#5436](https://github.com/dependabot/dependabot-core/pull/5436)
- Add a fix for when the image tag is the first entry in the array. (@brendandburns) [#5558](https://github.com/dependabot/dependabot-core/pull/5558)
- [terraform] Cache client-side timeouts when a remote host is unreachable [#5407](https://github.com/dependabot/dependabot-core/pull/5407)

## v0.209.0, 17 August 2022

- Ignore newlines when determining indentation [#5550](https://github.com/dependabot/dependabot-core/pull/5550)
- Allow diverged-commit pinned Actions to be updated [#5516](https://github.com/dependabot/dependabot-core/pull/5516)
- Add a dependabot implementation for Kubernetes YAML files. (@brendandburns) [#5348](https://github.com/dependabot/dependabot-core/pull/5348)
- The new pip resolver is not backwards compatible [#5540](https://github.com/dependabot/dependabot-core/pull/5540)

## v0.208.0, 16 August 2022

- Try fix spec failure due to broken setuptools [#5546](https://github.com/dependabot/dependabot-core/pull/5546)
- Share omnibus gems with all projects to reduce install time [#5529](https://github.com/dependabot/dependabot-core/pull/5529)
- build(deps): bump @dependabot/yarn-lib from 1.21.1 to 1.22.19 in /npm_and_yarn/helpers [#5531](https://github.com/dependabot/dependabot-core/pull/5531)
- Run shellcheck on all native helper build scripts [#5519](https://github.com/dependabot/dependabot-core/pull/5519)
- Python private registry authentication fix (@andrcuns) [#5452](https://github.com/dependabot/dependabot-core/pull/5452)
- Adds a TODO and more detailed comment about python 3.6 support [#5527](https://github.com/dependabot/dependabot-core/pull/5527)
- [Bitbucket] Add default reviewers to pull request (@stefangr) [#5526](https://github.com/dependabot/dependabot-core/pull/5526)
- Make failures in Bundler 1 native helper specs actually fail CI [#5517](https://github.com/dependabot/dependabot-core/pull/5517)
- Optional options arg for FileFetcher [#5524](https://github.com/dependabot/dependabot-core/pull/5524)
- Cleanup Ruby sources after installing Ruby [#5522](https://github.com/dependabot/dependabot-core/pull/5522)
- Remove ENV no longer necessary [#5515](https://github.com/dependabot/dependabot-core/pull/5515)

## v0.207.0, 11 August 2022

- Monkey patch bundler EndpointSpecification [#5510](https://github.com/dependabot/dependabot-core/pull/5510)
- Log reasons why npm audit can't succeed [#5512](https://github.com/dependabot/dependabot-core/pull/5512)

## v0.206.0, 10 August 2022

- Pin MessageBuilder cassette names [#5508](https://github.com/dependabot/dependabot-core/pull/5508)
- github_actions ecosystem was missing for debugging [#5505](https://github.com/dependabot/dependabot-core/pull/5505)
- Bump Elixir to `1.13.4` [#5502](https://github.com/dependabot/dependabot-core/pull/5502)
- build(deps-dev): update rubocop requirement from ~> 1.31.2 to ~> 1.33.0 in /common [#5498](https://github.com/dependabot/dependabot-core/pull/5498)
- build(deps): update pip requirement from <22.2.2,>=21.3.1 to >=21.3.1,<22.2.3 in /python/helpers [#5495](https://github.com/dependabot/dependabot-core/pull/5495)
- build(deps): bump flake8 from 5.0.3 to 5.0.4 in /python/helpers [#5496](https://github.com/dependabot/dependabot-core/pull/5496)
- Handle the new `go` build tag syntax [#4954](https://github.com/dependabot/dependabot-core/pull/4954)
- Tweak comment now that `pip` has a resolver [#5491](https://github.com/dependabot/dependabot-core/pull/5491)
- Bump to `go` `1.19` [#5490](https://github.com/dependabot/dependabot-core/pull/5490)
- Disable `pip` latest version check when building `python` native helper [#5493](https://github.com/dependabot/dependabot-core/pull/5493)
- [npm] Refactor with top-down traversal [#5439](https://github.com/dependabot/dependabot-core/pull/5439)
- build(deps): bump http from 0.13.4 to 0.13.5 in /pub/helpers [#5499](https://github.com/dependabot/dependabot-core/pull/5499)

## v0.205.1, 8 August 2022

- Add a `.ruby-version` file [#5483](https://github.com/dependabot/dependabot-core/pull/5483)
- build(deps): update octokit requirement from ~> 4.6 to >= 4.6, < 6.0 in /common [#5370](https://github.com/dependabot/dependabot-core/pull/5370)
- Migrate from `actions/setup-ruby` to `ruby/setup-ruby` [#5433](https://github.com/dependabot/dependabot-core/pull/5433)
- Add support for multi-level wildcard paths in composer [#5484](https://github.com/dependabot/dependabot-core/pull/5484)
- Skip installing docs when installing Ruby [#5482](https://github.com/dependabot/dependabot-core/pull/5482)
- Suppress "detached head" advice during `git clone` [#5476](https://github.com/dependabot/dependabot-core/pull/5476)
- Bitbucket does not support HTML in pull request message (@stefangr) [#5481](https://github.com/dependabot/dependabot-core/pull/5481)

## v0.205.0, 4 August 2022

- Downgrade bundler to 2.3.14 [#5479](https://github.com/dependabot/dependabot-core/pull/5479)
- build(deps): bump json-schema from 0.2.3 to 0.4.0 in /npm_and_yarn/helpers [#5425](https://github.com/dependabot/dependabot-core/pull/5425)
- Update ruby gems using the `--no-document` flag [#5471](https://github.com/dependabot/dependabot-core/pull/5471)
- build(deps-dev): bump eslint from 8.19.0 to 8.21.0 in /npm_and_yarn/helpers [#5455](https://github.com/dependabot/dependabot-core/pull/5455)
- build(deps): bump minimist from 1.2.5 to 1.2.6 in /npm_and_yarn/helpers [#5426](https://github.com/dependabot/dependabot-core/pull/5426)
- build(deps): bump cython from 0.29.30 to 0.29.32 in /python/helpers [#5457](https://github.com/dependabot/dependabot-core/pull/5457)
- build(deps): bump flake8 from 5.0.1 to 5.0.3 in /python/helpers [#5467](https://github.com/dependabot/dependabot-core/pull/5467)
- Allow Actions to be fetched from non-GitHub source [#5469](https://github.com/dependabot/dependabot-core/pull/5469)
- Reduce bundler version hardcoding (@deivid-rodriguez) [#4973](https://github.com/dependabot/dependabot-core/pull/4973)

## v0.204.0, 3 August 2022

- use a "shim" to fix inability to rewrite git commands to use HTTPS URLs [#5332](https://github.com/dependabot/dependabot-core/pull/5332)

## v0.203.0, 3 August 2022

- Make Dependabot watch the per-ecosystem gemspecs [#5460](https://github.com/dependabot/dependabot-core/pull/5460)
- build(deps): update pip requirement from <22.1.3,>=21.3.1 to >=21.3.1,<22.2.2 in /python/helpers [#5456](https://github.com/dependabot/dependabot-core/pull/5456)
- fix: set correct url for terraform module version download (@umglurf) [#5366](https://github.com/dependabot/dependabot-core/pull/5366)
- build(deps): bump @npmcli/arborist from 5.2.3 to 5.3.1 in /npm_and_yarn/helpers [#5458](https://github.com/dependabot/dependabot-core/pull/5458)
- build(deps): bump path-parse from 1.0.6 to 1.0.7 in /npm_and_yarn/helpers [#5427](https://github.com/dependabot/dependabot-core/pull/5427)
- GitLab: Extract local actions variable into method (@NobodysNightmare) [#5448](https://github.com/dependabot/dependabot-core/pull/5448)
- build(deps): bump flake8 from 4.0.1 to 5.0.1 in /python/helpers [#5454](https://github.com/dependabot/dependabot-core/pull/5454)
- Fix incomplete regular expression for hostnames [#5444](https://github.com/dependabot/dependabot-core/pull/5444)
- Bump base image in docker push workflow to `20.04` [#5432](https://github.com/dependabot/dependabot-core/pull/5432)
- Cache client-side timeouts when a remote host is unreachable for remaining ecosystems [#5408](https://github.com/dependabot/dependabot-core/pull/5408)
- Switch to weekly updates for Dependabot [#5435](https://github.com/dependabot/dependabot-core/pull/5435)
- Move comment to relevant section of code [#5434](https://github.com/dependabot/dependabot-core/pull/5434)
- Add dependabot updates for Dockerfiles [#5428](https://github.com/dependabot/dependabot-core/pull/5428)
- Re-order ecosystems lexicographically [#5429](https://github.com/dependabot/dependabot-core/pull/5429)
- build(deps): update faraday requirement from = 1.10.0 to = 2.3.0 in /common [#5197](https://github.com/dependabot/dependabot-core/pull/5197)

## v0.202.0, 26 July 2022

- [cargo] Cache client-side timeouts when a remote host is unreachable [#5402](https://github.com/dependabot/dependabot-core/pull/5402)
- [gomod] Cache client-side timeouts when a remote host is unreachable [#5401](https://github.com/dependabot/dependabot-core/pull/5401)
- fix: regex to support Gitlab subgroups (@argoyle) [#5297](https://github.com/dependabot/dependabot-core/pull/5297)
- fix(terraform): correctly keep platform hashes when multiple providers are installed (@Flydiverny) [#5341](https://github.com/dependabot/dependabot-core/pull/5341)

## v0.201.1, 25 July 2022

- [Cargo] Correctly handle unused subdependencies of path dependencies [#5414](https://github.com/dependabot/dependabot-core/pull/5414)
- [Nuget] Cache client-side timeouts when a remote host is unreachable [#5399](https://github.com/dependabot/dependabot-core/pull/5399)
- Tweak bump-version script to just push the newly-created tag [#5413](https://github.com/dependabot/dependabot-core/pull/5413)

## v0.201.0, 22 July 2022

- [Composer] Cache client-side timeouts when a remote host is unreachable [#5400](https://github.com/dependabot/dependabot-core/pull/5400)

## v0.200.0, 21 July 2022

- [Python] Cache client-side timeouts when a remote host is unreachable [#5374](https://github.com/dependabot/dependabot-core/pull/5374)
- Pip: Do not raise PathDependenciesNotReachable for missing setup.py [#5392](https://github.com/dependabot/dependabot-core/pull/5392)

## v0.199.0, 19 July 2022

- Stop skipping requirements with `original_link` [#5385](https://github.com/dependabot/dependabot-core/pull/5385)

## v0.198.0, 15 July 2022

- Bump go from 1.18.1 to 1.18.4 [#5379](https://github.com/dependabot/dependabot-core/pull/5379)
- [npm] Detect cycles when traversing vuln effects in helper and raise [#5321](https://github.com/dependabot/dependabot-core/pull/5321)

## v0.197.0, 15 July 2022

- [Bundler] Cache client-side timeouts when a remote host is unreachable [#5375](https://github.com/dependabot/dependabot-core/pull/5375)
- Bump bundler from 2.3.13 to 2.3.18 and fix script [#5382](https://github.com/dependabot/dependabot-core/pull/5382)
- Use new pip resolver for pip-compile [#5358](https://github.com/dependabot/dependabot-core/pull/5358)

## v0.196.4, 14 July 2022

- [NPM/YARN] Cache client-side timeouts when a remote host is unreachable [#5373](https://github.com/dependabot/dependabot-core/pull/5373)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.9.2 to 3.9.3 in /composer/helpers/v2 [#5378](https://github.com/dependabot/dependabot-core/pull/5378)
- build(deps-dev): bump jest from 28.1.2 to 28.1.3 in /npm_and_yarn/helpers [#5376](https://github.com/dependabot/dependabot-core/pull/5376)
- build(deps-dev): bump phpstan/phpstan from 1.8.0 to 1.8.1 in /composer/helpers/v2 [#5371](https://github.com/dependabot/dependabot-core/pull/5371)
- Update Ruby to version 2.7.6 [#5364](https://github.com/dependabot/dependabot-core/pull/5364)
- Install Ruby with ruby-install [#5356](https://github.com/dependabot/dependabot-core/pull/5356)
- Do not attribute `maintainers` in release notes [#5360](https://github.com/dependabot/dependabot-core/pull/5360)

## v0.196.3, 12 July 2022

- Add support for Python 3.10.5 & 3.9.13 (@ulgens) [#5333](https://github.com/dependabot/dependabot-core/pull/5333)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.8.0 to 3.9.2 in /composer/helpers/v2 [#5357](https://github.com/dependabot/dependabot-core/pull/5357)
- build(deps): update pip-tools requirement from <=6.6.2,>=6.4.0 to >=6.4.0,<6.8.1 in /python/helpers [#5337](https://github.com/dependabot/dependabot-core/pull/5337)
- build(deps-dev): update rubocop requirement from ~> 1.30.1 to ~> 1.31.2 in /common [#5350](https://github.com/dependabot/dependabot-core/pull/5350)
- build(deps): bump poetry from 1.1.13 to 1.1.14 in /python/helpers [#5354](https://github.com/dependabot/dependabot-core/pull/5354)
- build(deps): update gitlab requirement from = 4.18.0 to = 4.19.0 in /common [#5355](https://github.com/dependabot/dependabot-core/pull/5355)
- build(deps): bump nock from 13.2.7 to 13.2.8 in /npm_and_yarn/helpers [#5336](https://github.com/dependabot/dependabot-core/pull/5336)
- build(deps-dev): bump eslint from 8.18.0 to 8.19.0 in /npm_and_yarn/helpers [#5343](https://github.com/dependabot/dependabot-core/pull/5343)
- build(deps): bump cython from 0.29.28 to 0.29.30 in /python/helpers [#5158](https://github.com/dependabot/dependabot-core/pull/5158)
- build(deps-dev): bump jest from 28.1.1 to 28.1.2 in /npm_and_yarn/helpers [#5328](https://github.com/dependabot/dependabot-core/pull/5328)
- build(deps-dev): bump phpstan/phpstan from 1.7.15 to 1.8.0 in /composer/helpers/v2 [#5330](https://github.com/dependabot/dependabot-core/pull/5330)
- build(deps): bump composer/composer from 2.3.5 to 2.3.9 in /composer/helpers/v2 [#5347](https://github.com/dependabot/dependabot-core/pull/5347)
- [go_mod] Stub failed response for initial go get call [#5335](https://github.com/dependabot/dependabot-core/pull/5335)
- [npm] Ensure 'fix_updates' field in `VulnerabilityAuditor#audit` response (@bdragon) [#5334](https://github.com/dependabot/dependabot-core/pull/5334)
- Disable potential script execution in arborist [#5327](https://github.com/dependabot/dependabot-core/pull/5327)

## v0.196.2, 29 June 2022

- Configure arborist registries from npm config [#5313](https://github.com/dependabot/dependabot-core/pull/5313)
- Yarn: support recursive paths expansion (@FunkyloverOne) [#5231](https://github.com/dependabot/dependabot-core/pull/5231)

## v0.196.1, 27 June 2022

- Fix rubocop configuration error [#5318](https://github.com/dependabot/dependabot-core/pull/5318)
- build(deps-dev): bump jest from 28.1.0 to 28.1.1 in /npm_and_yarn/helpers [#5243](https://github.com/dependabot/dependabot-core/pull/5243)
- build(deps-dev): bump phpstan/phpstan from 1.7.14 to 1.7.15 in /composer/helpers/v1 [#5290](https://github.com/dependabot/dependabot-core/pull/5290)
- build(deps-dev): bump phpstan/phpstan from 1.6.8 to 1.7.15 in /composer/helpers/v2 [#5291](https://github.com/dependabot/dependabot-core/pull/5291)
- build(deps): bump nock from 13.2.4 to 13.2.7 in /npm_and_yarn/helpers [#5316](https://github.com/dependabot/dependabot-core/pull/5316)
- build(deps): bump @npmcli/arborist from 5.2.0 to 5.2.3 in /npm_and_yarn/helpers [#5306](https://github.com/dependabot/dependabot-core/pull/5306)
- Prioritize target dependency in transitive dependency updates [#5311](https://github.com/dependabot/dependabot-core/pull/5311)

## v0.196.0, 24 June 2022

- [npm] Initial support for locked transitive dependency updates [#5239](https://github.com/dependabot/dependabot-core/pull/5239)

## v0.195.0, 24 June 2022

- Rebuild dependabot-core image in CI Workflow (@mattt) [#5307](https://github.com/dependabot/dependabot-core/pull/5307)
- Update logo in README (@mattt) [#5298](https://github.com/dependabot/dependabot-core/pull/5298)
- Update pub revision (@sigurdm) [#5272](https://github.com/dependabot/dependabot-core/pull/5272)
- Remove Image Caching from CI Workflow (@mattt) [#5295](https://github.com/dependabot/dependabot-core/pull/5295)

## v0.194.1, 20 June 2022

- build(deps-dev): update debase-ruby_core_source requirement from = 0.10.14 to = 0.10.16 in /common [#5173](https://github.com/dependabot/dependabot-core/pull/5173)
- build(deps-dev): bump eslint from 8.15.0 to 8.18.0 in /npm_and_yarn/helpers [#5285](https://github.com/dependabot/dependabot-core/pull/5285)
- build(deps-dev): update rubocop requirement from ~> 1.29.1 to ~> 1.30.1 in /common [#5235](https://github.com/dependabot/dependabot-core/pull/5235)
- Setup Dependabot for the Pub helpers [#5289](https://github.com/dependabot/dependabot-core/pull/5289)
- Handle beta dart releases (@sigurdm) [#5286](https://github.com/dependabot/dependabot-core/pull/5286)

## v0.194.0, 17 June 2022

- Updates TERRAFORM_VERSION in Dockerfile to version 1.2.3 (@joberget) [#5274](https://github.com/dependabot/dependabot-core/pull/5274)

## v0.193.0, 16 June 2022

- Revert "build(deps-dev): bump phpstan/phpstan from 1.6.8 to 1.7.14 in /composer/helpers/v2" (@jakecoffman) [#5278](https://github.com/dependabot/dependabot-core/pull/5278)
- build(deps-dev): bump phpstan/phpstan from 1.6.8 to 1.7.14 in /composer/helpers/v2 [#5266](https://github.com/dependabot/dependabot-core/pull/5266)
- Update NPM package name validation rules (@mattt) [#5259](https://github.com/dependabot/dependabot-core/pull/5259)
- build(deps-dev): bump phpstan/phpstan from 1.6.8 to 1.7.14 in /composer/helpers/v1 [#5267](https://github.com/dependabot/dependabot-core/pull/5267)
- build(deps-dev): bump prettier from 2.6.2 to 2.7.1 in /npm_and_yarn/helpers [#5270](https://github.com/dependabot/dependabot-core/pull/5270)
- cargo: handle patch with path that is a submodule (@jakecoffman) [#5250](https://github.com/dependabot/dependabot-core/pull/5250)

## v0.192.1, 14 June 2022

- Bump pub revision to fix error without lockfile [#5263](https://github.com/dependabot/dependabot-core/pull/5263)

## v0.192.0, 13 June 2022

- Use inferred flutter version (@sigurdm) [#5207](https://github.com/dependabot/dependabot-core/pull/5207)

## v0.191.1, 13 June 2022

- Only report conflicting dependencies when update is not possible (@deivid-rodriguez) [#5237](https://github.com/dependabot/dependabot-core/pull/5237)
- build(deps): update pip requirement from <=22.1.1,>=21.3.1 to >=21.3.1,<22.1.3 in /python/helpers [#5212](https://github.com/dependabot/dependabot-core/pull/5212)
- Fix Yarn ignored path checking (@FunkyloverOne) [#5220](https://github.com/dependabot/dependabot-core/pull/5220)

## v0.191.0, 7 June 2022

- poetry: fixes for broken lockfile and leaked credentials (@jakecoffman) [#5222](https://github.com/dependabot/dependabot-core/pull/5222)
- Check if updated file exists before adding to list of terraform updated files (@dwc0011) [#5168](https://github.com/dependabot/dependabot-core/pull/5168)
- Print package manager version instrumentation events in the dry runner (@Nishnha) [#5194](https://github.com/dependabot/dependabot-core/pull/5194)
- Instrument npm version (@Nishnha) [#5187](https://github.com/dependabot/dependabot-core/pull/5187)

## v0.190.1, 31 May 2022

- Update pub revision (@sigurdm) [#5203](https://github.com/dependabot/dependabot-core/pull/5203)
- Update test cases with new hashes returned from npm registry [#5208](https://github.com/dependabot/dependabot-core/pull/5208)
- Upgrade pip inside of any newly created pyenv (@pavera) [#5195](https://github.com/dependabot/dependabot-core/pull/5195)
- Document why the link needs to be unescaped (@jeffwidman) [#5186](https://github.com/dependabot/dependabot-core/pull/5186)
- URL decode Nuget API v2 "next" link when paging version results (@tomcain) [#5174](https://github.com/dependabot/dependabot-core/pull/5174)

## v0.190.0, 23 May 2022

- Git dependency support for pub (@sigurdm) [#5102](https://github.com/dependabot/dependabot-core/pull/5102)
- Remove versions from comments (@jeffwidman) [#5181](https://github.com/dependabot/dependabot-core/pull/5181)
- Cargo: Update rust toolchain to 1.61.0 (@DarkKirb) [#5180](https://github.com/dependabot/dependabot-core/pull/5180)
- Bump Terraform from 1.0.16 to 1.2.0 (@andrassy) [#5170](https://github.com/dependabot/dependabot-core/pull/5170)
- fix required checks not run during a release (@jakecoffman) [#5144](https://github.com/dependabot/dependabot-core/pull/5144)

## v0.189.0, 17 May 2022

- Revert "Strip UTF-8 BOM from file contents" (@mattt) [#5145](https://github.com/dependabot/dependabot-core/pull/5145)
- [Maven] Cache client-side timeouts when a remote host is unreachable (@brrygrdn) [#5142](https://github.com/dependabot/dependabot-core/pull/5142)
- build(deps): bump @npmcli/arborist from 5.1.0 to 5.2.0 in /npm_and_yarn/helpers [#5133](https://github.com/dependabot/dependabot-core/pull/5133)

## v0.188.0, 16 May 2022

- Dwc0011/fix codecommit error (@dwc0011) [#4926](https://github.com/dependabot/dependabot-core/pull/4926)
- Upgrade Python to 3.10.4 and support newer releases (@henrikhorluck) [#4976](https://github.com/dependabot/dependabot-core/pull/4976)
- build(deps): bump npm from 6.14.16 to 6.14.17 in /npm_and_yarn/helpers [#5067](https://github.com/dependabot/dependabot-core/pull/5067)
- build(deps-dev): bump eslint from 8.13.0 to 8.15.0 in /npm_and_yarn/helpers [#5106](https://github.com/dependabot/dependabot-core/pull/5106)
- build(deps-dev): bump jest from 27.5.1 to 28.1.0 in /npm_and_yarn/helpers [#5105](https://github.com/dependabot/dependabot-core/pull/5105)
- build(deps-dev): bump phpstan/phpstan from 1.6.4 to 1.6.8 in /composer/helpers/v2 [#5126](https://github.com/dependabot/dependabot-core/pull/5126)
- build(deps-dev): bump phpstan/phpstan from 1.6.4 to 1.6.8 in /composer/helpers/v1 [#5127](https://github.com/dependabot/dependabot-core/pull/5127)
- build(deps-dev): update rubocop requirement from ~> 1.28.2 to ~> 1.29.1 in /common [#5136](https://github.com/dependabot/dependabot-core/pull/5136)
- skip CI workflow when creating release notes (@jakecoffman) [#5139](https://github.com/dependabot/dependabot-core/pull/5139)
- Strip UTF-8 BOM from file contents (@mattt) [#5129](https://github.com/dependabot/dependabot-core/pull/5129)

## v0.187.0, 13 May 2022

- Fix Bundler v2 related TODOs (@deivid-rodriguez) [#5034](https://github.com/dependabot/dependabot-core/pull/5034)
- Add --network-trace to dry-run (@brrygrdn) [#5131](https://github.com/dependabot/dependabot-core/pull/5131)
- [Maven] Fix some malformed memoizations (@brrygrdn) [#5132](https://github.com/dependabot/dependabot-core/pull/5132)
- bundler: upgrade to 2.3.13 for rubygems/rubygems#5492 (@jakecoffman) [#5134](https://github.com/dependabot/dependabot-core/pull/5134)
- [Maven] Avoid retrying requests to repos excessively (@brrygrdn) [#5130](https://github.com/dependabot/dependabot-core/pull/5130)
- Fix Dependabot ignoring scoped registries if the lockfile resolved uri contains a port number (@brrygrdn) [#5124](https://github.com/dependabot/dependabot-core/pull/5124)

## v0.186.1, 10 May 2022

- Validate before creating version objects in `Dependabot::NpmAndYarn::UpdateChecker::VersionResolver` (@mattt) [#5120](https://github.com/dependabot/dependabot-core/pull/5120)
- Fix implementation of `PackageName#library_name` (@mattt) [#5119](https://github.com/dependabot/dependabot-core/pull/5119)
- Clarify comment and remove TODO (@jeffwidman) [#5031](https://github.com/dependabot/dependabot-core/pull/5031)
- Bump `go` to `1.18.1` (@jeffwidman) [#5029](https://github.com/dependabot/dependabot-core/pull/5029)

## v0.186.0, 10 May 2022

- Updating a package and its related @types package simultaneously (@pavera) [#5000](https://github.com/dependabot/dependabot-core/pull/5000)
- Remove and ignore `.tool-versions` (@mattt) [#5114](https://github.com/dependabot/dependabot-core/pull/5114)
- Add fixtures to `paths-ignore` for CodeQL workflow (@mattt) [#5113](https://github.com/dependabot/dependabot-core/pull/5113)
- Fix code scanning alerts for incomplete sanitization of URL substrings (@mattt) [#5108](https://github.com/dependabot/dependabot-core/pull/5108)

## v0.185.0, 9 May 2022

- fix DependencyFileNotParseable due to 1MB file limit change (@jakecoffman) [#5107](https://github.com/dependabot/dependabot-core/pull/5107)
- pin debase version to avoid build errors (@pavera) [#5086](https://github.com/dependabot/dependabot-core/pull/5086)

## v0.184.0, 4 May 2022

- nuget: fix PR missing commits in message when using private registry (@jakecoffman) [#5072](https://github.com/dependabot/dependabot-core/pull/5072)
- [Maven] Avoid an infinite loop if the default branch for a dependency 404s (@brrygrdn) [#5091](https://github.com/dependabot/dependabot-core/pull/5091)
- build(deps): bump github/codeql-action from 1 to 2 [#5053](https://github.com/dependabot/dependabot-core/pull/5053)
- Prevent Dependabot from downgrading Dockerfiles if the repository doesn't have the tag yet (@brrygrdn) [#5087](https://github.com/dependabot/dependabot-core/pull/5087)
- build(deps-dev): update rubocop requirement from ~> 1.27.0 to ~> 1.28.2 in /common [#5050](https://github.com/dependabot/dependabot-core/pull/5050)
- build(deps-dev): bump phpstan/phpstan from 1.5.6 to 1.6.4 in /composer/helpers/v2 [#5080](https://github.com/dependabot/dependabot-core/pull/5080)
- build(deps-dev): bump phpstan/phpstan from 1.5.6 to 1.6.4 in /composer/helpers/v1 [#5081](https://github.com/dependabot/dependabot-core/pull/5081)
- remove multiplicative retries to improve system health (@jakecoffman) [#5085](https://github.com/dependabot/dependabot-core/pull/5085)
- fix debase build errors (@jakecoffman) [#5078](https://github.com/dependabot/dependabot-core/pull/5078)

## v0.183.0, 29 April 2022

- fix unsafe directory git issues during updates (@jakecoffman) [#5065](https://github.com/dependabot/dependabot-core/pull/5065)

## v0.182.4, 26 April 2022

- Rollback RubyGems from 3.3.11 to 3.2.20 (@mctofu) [#5048](https://github.com/dependabot/dependabot-core/pull/5048)

## v0.182.3, 25 April 2022

- Set BUNDLER_VERSION to the specific installed version in native helpers (@brrygrdn) [#5044](https://github.com/dependabot/dependabot-core/pull/5044)

## v0.182.2, 25 April 2022

- Manually revert "nuget: fix PR missing commits in message when using private registry" (@brrygrdn) [#5040](https://github.com/dependabot/dependabot-core/pull/5040)

## v0.182.1, 25 April 2022

- Prevent KeyError when checking search results (@brrygrdn) [#5038](https://github.com/dependabot/dependabot-core/pull/5038)
- Update RubyGems and use `--no-document` for updating it (@deivid-rodriguez) [#5035](https://github.com/dependabot/dependabot-core/pull/5035)
- Translate from `@types` package to library name (@landongrindheim) [#5025](https://github.com/dependabot/dependabot-core/pull/5025)
- Add ecosystem-specific code owners (@mattt) [#4614](https://github.com/dependabot/dependabot-core/pull/4614)
- fix typos in GitHub issue bug report template (@tyrann0us) [#5015](https://github.com/dependabot/dependabot-core/pull/5015)
- Update Bundler from 2.3.10 to 2.3.12 (@deivid-rodriguez) [#5018](https://github.com/dependabot/dependabot-core/pull/5018)
- build(deps): bump @npmcli/arborist from 5.0.6 to 5.1.0 in /npm_and_yarn/helpers [#5020](https://github.com/dependabot/dependabot-core/pull/5020)
- Use a temporary Ruby requirement for updating lockfile (@deivid-rodriguez) [#5019](https://github.com/dependabot/dependabot-core/pull/5019)

## v0.182.0, 19 April 2022

- Automate Terraform Platform Detection for Lockfile Hashes [#4905](https://github.com/dependabot/dependabot-core/pull/4905)

## v0.181.0, 19 April 2022

- nuget: fix PR missing commits in message when using private registry [#5002](https://github.com/dependabot/dependabot-core/pull/5002)
- Map Package Name to Types Package Name [#5001](https://github.com/dependabot/dependabot-core/pull/5001)
- build(deps-dev): bump phpstan/phpstan from 1.5.5 to 1.5.6 in /composer/helpers/v2 [#5010](https://github.com/dependabot/dependabot-core/pull/5010)
- build(deps-dev): bump phpstan/phpstan from 1.5.5 to 1.5.6 in /composer/helpers/v1 [#5007](https://github.com/dependabot/dependabot-core/pull/5007)
- build(deps-dev): bump phpstan/phpstan from 1.5.4 to 1.5.5 in /composer/helpers/v1 [#5005](https://github.com/dependabot/dependabot-core/pull/5005)
- build(deps-dev): bump phpstan/phpstan from 1.5.4 to 1.5.5 in /composer/helpers/v2 [#5004](https://github.com/dependabot/dependabot-core/pull/5004)
- build(deps): bump composer/composer from 1.10.25 to 1.10.26 in /composer/helpers/v1 [#4996](https://github.com/dependabot/dependabot-core/pull/4996)
- build(deps): bump @npmcli/arborist from 5.0.5 to 5.0.6 in /npm_and_yarn/helpers [#4994](https://github.com/dependabot/dependabot-core/pull/4994)
- build(deps): bump composer/composer from 2.3.4 to 2.3.5 in /composer/helpers/v2 [#4995](https://github.com/dependabot/dependabot-core/pull/4995)
- build(deps): bump semver from 7.3.6 to 7.3.7 in /npm_and_yarn/helpers [#4990](https://github.com/dependabot/dependabot-core/pull/4990)
- Adds failing tests for Typescript @types updates [#4992](https://github.com/dependabot/dependabot-core/pull/4992)
- handle multiple python manifests containing the same dependency [#4969](https://github.com/dependabot/dependabot-core/pull/4969)
- Python: unwrap arbitrary parentheses from requirement string [#4988](https://github.com/dependabot/dependabot-core/pull/4988)
- Adding ability to debug into tests from VS Code [#4971](https://github.com/dependabot/dependabot-core/pull/4971)
- build(deps): bump composer/composer from 2.3.3 to 2.3.4 in /composer/helpers/v2 [#4978](https://github.com/dependabot/dependabot-core/pull/4978)
- build(deps): bump @npmcli/arborist from 5.0.4 to 5.0.5 in /npm_and_yarn/helpers [#4977](https://github.com/dependabot/dependabot-core/pull/4977)
- build(deps-dev): update rubocop requirement from ~> 1.26.0 to ~> 1.27.0 in /common [#4986](https://github.com/dependabot/dependabot-core/pull/4986)
- build(deps): bump pipenv from 2022.3.28 to 2022.4.8 in /python/helpers [#4985](https://github.com/dependabot/dependabot-core/pull/4985)
- build(deps-dev): bump eslint from 8.12.0 to 8.13.0 in /npm_and_yarn/helpers [#4984](https://github.com/dependabot/dependabot-core/pull/4984)
- pub: Bump when publish to none (@sigurdm) [#4981](https://github.com/dependabot/dependabot-core/pull/4981)
- Fix terraform update_range function [#4982](https://github.com/dependabot/dependabot-core/pull/4982)
- Restore python 3.6 support [#4958](https://github.com/dependabot/dependabot-core/pull/4958)

## v0.180.5, 7 April 2022

- Actions: Fix failed update if version was a partial match for a branch [#4972](https://github.com/dependabot/dependabot-core/pull/4972)
- build(deps-dev): bump eslint-config-prettier from 8.3.0 to 8.5.0 in /npm_and_yarn/helpers [#4788](https://github.com/dependabot/dependabot-core/pull/4788)
- build(deps-dev): bump jest from 27.4.7 to 27.5.1 in /npm_and_yarn/helpers [#4719](https://github.com/dependabot/dependabot-core/pull/4719)
- build(deps-dev): bump eslint from 8.7.0 to 8.12.0 in /npm_and_yarn/helpers [#4918](https://github.com/dependabot/dependabot-core/pull/4918)
- added php mcrypt extension (@oleg-andreyev) [#4170](https://github.com/dependabot/dependabot-core/pull/4170)
- build(deps): bump actions/checkout from 2 to 3 [#4783](https://github.com/dependabot/dependabot-core/pull/4783)
- build(deps): bump semver from 7.3.5 to 7.3.6 in /npm_and_yarn/helpers [#4965](https://github.com/dependabot/dependabot-core/pull/4965)
- Allow open_timeout to be configured by ENV var [#4964](https://github.com/dependabot/dependabot-core/pull/4964)
- code is unsused: main packages have no particular effect on dependencies [#4962](https://github.com/dependabot/dependabot-core/pull/4962)

## v0.180.4, 6 April 2022

- Actions: Consider precision of current version when selecting latest [#4953](https://github.com/dependabot/dependabot-core/pull/4953)
- build(deps): bump composer/composer from 2.2.9 to 2.3.3 in /composer/helpers/v2 [#4944](https://github.com/dependabot/dependabot-core/pull/4944)
- Update bundler from 2.3.9 to 2.3.10 (@schinery) [#4961](https://github.com/dependabot/dependabot-core/pull/4961)
- build(deps): bump @npmcli/arborist from 5.0.3 to 5.0.4 in /npm_and_yarn/helpers [#4960](https://github.com/dependabot/dependabot-core/pull/4960)
- Update pub dependency service (@sigurdm) [#4957](https://github.com/dependabot/dependabot-core/pull/4957)
- build(deps-dev): bump phpstan/phpstan from 1.4.10 to 1.5.4 in /composer/helpers/v2 [#4946](https://github.com/dependabot/dependabot-core/pull/4946)
- build(deps-dev): bump phpstan/phpstan from 1.4.10 to 1.5.4 in /composer/helpers/v1 [#4945](https://github.com/dependabot/dependabot-core/pull/4945)
- build(deps-dev): bump prettier from 2.6.0 to 2.6.2 in /npm_and_yarn/helpers [#4943](https://github.com/dependabot/dependabot-core/pull/4943)
- build(deps): bump github.com/Masterminds/vcs from 1.13.1 to 1.13.3 in /go_modules/helpers [#4942](https://github.com/dependabot/dependabot-core/pull/4942)
- Cargo: Update specs to reference latest version of dependency used [#4956](https://github.com/dependabot/dependabot-core/pull/4956)

## v0.180.3, 4 April 2022

- Add support for Python packages with epoch version [#4928](https://github.com/dependabot/dependabot-core/pull/4928)
- fix error due to not handling case statements in Gemfile [#4949](https://github.com/dependabot/dependabot-core/pull/4949)
- Remove unnecessary get_directory special cases for npm_and_yarn (@ianlyons) [#4840](https://github.com/dependabot/dependabot-core/pull/4840)
- Dockerfile: arm64 support (@thepwagner) [#4858](https://github.com/dependabot/dependabot-core/pull/4858)
- Bump bundler from 2.3.8 to 2.3.9 and automate it [#4884](https://github.com/dependabot/dependabot-core/pull/4884)
- Remove workaround for broken ruby gems compare (@jeffwidman) [#4933](https://github.com/dependabot/dependabot-core/pull/4933)
- Fix typo (@jeffwidman) [#4932](https://github.com/dependabot/dependabot-core/pull/4932)
- Add Ruby 3.1.1 to RubyRequirementSetter version requirements (@schinery) [#4912](https://github.com/dependabot/dependabot-core/pull/4912)
- Cargo: Update rust toolchain to 1.59.0 [#4921](https://github.com/dependabot/dependabot-core/pull/4921)
- Metadetafinders: Use the default branch instead of master for gitlab (@dennisvandehoef) [#4916](https://github.com/dependabot/dependabot-core/pull/4916)
- build(deps): bump pip from 21.3.1 to 22.0.4 in /python/helpers [#4809](https://github.com/dependabot/dependabot-core/pull/4809)
- Add option `get` to regex that match the `go` cmd (@jeffwidman) [#4911](https://github.com/dependabot/dependabot-core/pull/4911)
- Handle when `go: downloading` is emitted before an unknown revision error (@jeffwidman) [#4910](https://github.com/dependabot/dependabot-core/pull/4910)
- build(deps): bump pipenv from 2022.3.24 to 2022.3.28 in /python/helpers [#4919](https://github.com/dependabot/dependabot-core/pull/4919)
- Bump eslint-plugin-prettier from 2.0.1 to 2.1.1 in /helpers/javascript (@dependabot-preview) [#1](https://github.com/dependabot/dependabot-core/pull/1)

## v0.180.2, 28 March 2022

- Add raise_on_ignore support to Pub [#4894](https://github.com/dependabot/dependabot-core/pull/4894)
- Bump Dart and Flutter to latest stable versions [#4904](https://github.com/dependabot/dependabot-core/pull/4904)
- Explicitly import process in npm_and_yarn helper [#4892](https://github.com/dependabot/dependabot-core/pull/4892)
- build(deps): bump pipenv from 2022.1.8 to 2022.3.24 in /python/helpers [#4900](https://github.com/dependabot/dependabot-core/pull/4900)

## v0.180.1, 23 March 2022

- Npm: Handle `.tar.gz` extensions for path dependencies [#4889](https://github.com/dependabot/dependabot-core/pull/4889)
- Update pub dependency_service (@sigurdm) [#4890](https://github.com/dependabot/dependabot-core/pull/4890)
- fixed a bug and improved testing around NuGet version compare [#4881](https://github.com/dependabot/dependabot-core/pull/4881)
- Fix Ruby version conflict error detection for new Bundler versions (@deivid-rodriguez) [#4820](https://github.com/dependabot/dependabot-core/pull/4820)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.4.0 to 3.8.0 in /composer/helpers/v2 [#4883](https://github.com/dependabot/dependabot-core/pull/4883)
- Reenable commented out failing specs (@deivid-rodriguez) [#4882](https://github.com/dependabot/dependabot-core/pull/4882)
- Update Gitlab approvers logic on pr creation (@andrcuns) [#4747](https://github.com/dependabot/dependabot-core/pull/4747)
- build(deps): update gitlab requirement from = 4.17.0 to = 4.18.0 in /common [#4872](https://github.com/dependabot/dependabot-core/pull/4872)
- build(deps-dev): bump phpstan/phpstan from 1.4.2 to 1.4.10 in /composer/helpers/v1 [#4850](https://github.com/dependabot/dependabot-core/pull/4850)
- Improve file_fetcher for GitHub Actions (@JonasAlfredsson) [#4815](https://github.com/dependabot/dependabot-core/pull/4815)
- build(deps-dev): bump phpstan/phpstan from 1.4.2 to 1.4.10 in /composer/helpers/v2 [#4849](https://github.com/dependabot/dependabot-core/pull/4849)
- build(deps): update faraday requirement from = 1.7.0 to = 1.10.0 in /common [#4871](https://github.com/dependabot/dependabot-core/pull/4871)
- build(deps-dev): update rubocop requirement from ~> 1.23.0 to ~> 1.26.0 in /common [#4870](https://github.com/dependabot/dependabot-core/pull/4870)
- build(deps): bump composer/composer from 2.2.6 to 2.2.9 in /composer/helpers/v2 [#4861](https://github.com/dependabot/dependabot-core/pull/4861)
- build(deps-dev): bump prettier from 2.5.1 to 2.6.0 in /npm_and_yarn/helpers [#4880](https://github.com/dependabot/dependabot-core/pull/4880)
- pub metadata_finder: Fall back to `homepage` if `repository` is not present (@sigurdm) [#4879](https://github.com/dependabot/dependabot-core/pull/4879)

## v0.180.0, 18 March 2022

- Upgrade main Python version to 3.10.3 (@ulgens) [#4874](https://github.com/dependabot/dependabot-core/pull/4874)
- build(deps): bump @npmcli/arborist from 4.2.1 to 5.0.3 in /npm_and_yarn/helpers [#4877](https://github.com/dependabot/dependabot-core/pull/4877)
- Modify ENV in a friendlier way during specs (@deivid-rodriguez) [#4865](https://github.com/dependabot/dependabot-core/pull/4865)
- Bump to `go` `1.18` (@jeffwidman) [#4853](https://github.com/dependabot/dependabot-core/pull/4853)
- Fix Bundler 1 spec failures (@deivid-rodriguez) [#4869](https://github.com/dependabot/dependabot-core/pull/4869)
- Require Ruby 2.7 (@deivid-rodriguez) [#4864](https://github.com/dependabot/dependabot-core/pull/4864)
- Bugfix: Include space in regex capturing group (@jeffwidman) [#4868](https://github.com/dependabot/dependabot-core/pull/4868)
- Get bundler specs green when run on Ruby 3.1 (@deivid-rodriguez) [#4841](https://github.com/dependabot/dependabot-core/pull/4841)
- NuGet version comparison fix [#4862](https://github.com/dependabot/dependabot-core/pull/4862)

## v0.179.0, 16 March 2022

- Bump Ubuntu to 20.04 (@jeffwidman) [#4394](https://github.com/dependabot/dependabot-core/pull/4394)
- Use expanded path when DEPENDABOT_NATIVE_HELPERS_PATH not set (@deivid-rodriguez) [#4844](https://github.com/dependabot/dependabot-core/pull/4844)
- Fix flaky spec failure on Bundler 1 suite (@deivid-rodriguez) [#4846](https://github.com/dependabot/dependabot-core/pull/4846)
- Unify RSpec requirements in helpers Gemfiles to match dependabot-common (@deivid-rodriguez) [#4843](https://github.com/dependabot/dependabot-core/pull/4843)
- Remove duplicated spec (@deivid-rodriguez) [#4839](https://github.com/dependabot/dependabot-core/pull/4839)
- Fix webmock requirement in helpers Gemfiles to match dependabot-common (@deivid-rodriguez) [#4838](https://github.com/dependabot/dependabot-core/pull/4838)
- Enable codeql [#4817](https://github.com/dependabot/dependabot-core/pull/4817)
- Improve `DEBUG_HELPERS` output (@deivid-rodriguez) [#4827](https://github.com/dependabot/dependabot-core/pull/4827)
- Fix some specs to pass outside of Docker (@deivid-rodriguez) [#4835](https://github.com/dependabot/dependabot-core/pull/4835)

## v0.178.1, 11 March 2022

- Fixes comparison between prerelease identifiers for NuGet [#4833](https://github.com/dependabot/dependabot-core/pull/4833)

## v0.178.0, 10 March 2022

- Disable spec fetching retries which are not functioning properly [#4823](https://github.com/dependabot/dependabot-core/pull/4823)
- build(deps): bump cython from 0.29.27 to 0.29.28 in /python/helpers [#4750](https://github.com/dependabot/dependabot-core/pull/4750)
- Update ci-test script to use bundler 2.3.8 (@deivid-rodriguez) [#4824](https://github.com/dependabot/dependabot-core/pull/4824)
- Bump erlang from 23.3.4.5 to 24.2.1 [#4816](https://github.com/dependabot/dependabot-core/pull/4816)
- Remove unnecessary pub cert config [#4814](https://github.com/dependabot/dependabot-core/pull/4814)
- Pin nuget vcr cassette names [#4818](https://github.com/dependabot/dependabot-core/pull/4818)
- github_actions: Add support for Composite Actions (@JonasAlfredsson) [#4755](https://github.com/dependabot/dependabot-core/pull/4755)
- Note that the `--dir` flag is required for subdirs (@jeffwidman) [#4812](https://github.com/dependabot/dependabot-core/pull/4812)
- Fix `detect_indentation` nil access error [#4802](https://github.com/dependabot/dependabot-core/pull/4802)

## v0.177.0, 4 March 2022

- Pub: use system root certificates [#4794](https://github.com/dependabot/dependabot-core/pull/4794)
- Bump bundler to 2.3.8 [#4786](https://github.com/dependabot/dependabot-core/pull/4786)
- pub support for requirement_update_strategy (@sigurdm) [#4778](https://github.com/dependabot/dependabot-core/pull/4778)
- Attempt to fix `*-*` range handling (@Danielku15) [#4749](https://github.com/dependabot/dependabot-core/pull/4749)
- Update NuGet to fetch packages using SemVer 2 [#4255](https://github.com/dependabot/dependabot-core/pull/4255)
- Update npm 7 references to npm 8 [#4771](https://github.com/dependabot/dependabot-core/pull/4771)
- build(deps): bump object-path from 0.11.5 to 0.11.8 in /npm_and_yarn/helpers [#4772](https://github.com/dependabot/dependabot-core/pull/4772)

## v0.176.0, 28 February 2022

- Beta: Dart/Flutter pub support (@sigurdm) [#4510](https://github.com/dependabot/dependabot-core/pull/4510)
  While now available in dependabot-core, this will require some more work before we
  can roll this out in the GitHub-hosted version of Dependabot.
- Disable flaky bundler1 test [#4767](https://github.com/dependabot/dependabot-core/pull/4767)

## v0.175.0, 25 February 2022

- Update to npm 8 [#4763](https://github.com/dependabot/dependabot-core/pull/4763)
  This includes a subtle change with how indentation in lockfiles is handled, in
  npm 8 the indentation from the package.json file is used, whereas before the
  package-lock.json would keep it's own indentation. Other than that 8 should be
  mostly backwards compatible. We suggest updating to npm 8 though, as 7 is no
  longer officially supported by the npm team.

## v0.174.1, 22 February 2022

- Temporarily revert Docker arg from support [#4759](https://github.com/dependabot/dependabot-core/pull/4759)
- Fix references to changelog path/contents in bump_version.rb [#4756](https://github.com/dependabot/dependabot-core/pull/4756)

## v0.174.0, 18 February 2022

- Bump Terraform from 1.0.11 to 1.1.6 [#4748](https://github.com/dependabot/dependabot-core/pull/4748)
- Codecommit pr release bugfix (@dwc0011) [#4745](https://github.com/dependabot/dependabot-core/pull/4745)
- Support depname.version = "1.2.3" syntax in TOML (@roblabla) [#4738](https://github.com/dependabot/dependabot-core/pull/4738)
- Add `--dry-run` flag to `bump-version` script [#4736](https://github.com/dependabot/dependabot-core/pull/4736)

## v0.173.0, 14 February 2022

- Update node to latest LTS version (16.x) [#4733](https://github.com/dependabot/dependabot-core/pull/4733)
- build(deps): bump poetry from 1.1.12 to 1.1.13 in /python/helpers [#4732](https://github.com/dependabot/dependabot-core/pull/4732)

## v0.172.2, 10 February 2022

- Bump go from 1.17.5 to 1.17.7 [#4730](https://github.com/dependabot/dependabot-core/pull/4730)

## v0.172.1, 9 February 2022

- Docker: Ignore ARGs without default values [#4723](https://github.com/dependabot/dependabot-core/pull/4723)
- build(deps): bump pip-tools from 6.5.0 to 6.5.1 in /python/helpers [#4718](https://github.com/dependabot/dependabot-core/pull/4718)

## v0.172.0, 9 February 2022

- Verify the right version of composer is installed in helper and docker [#4716](https://github.com/dependabot/dependabot-core/pull/4716)
- Bump composer v1 binary from 1.10.24 to 1.10.25 [#4717](https://github.com/dependabot/dependabot-core/pull/4717)
- Docker: Support ARG FROM (@hfhbd) [#4598](https://github.com/dependabot/dependabot-core/pull/4598)
- Fix peer dependency regex for cases with 2 semver constraints (@FaHeymann) [#4693](https://github.com/dependabot/dependabot-core/pull/4693)
- build(deps): bump composer/composer from 2.2.5 to 2.2.6 in /composer/helpers/v2 [#4708](https://github.com/dependabot/dependabot-core/pull/4708)
- Link to GitHub feedback discussion for Dependabot [#4714](https://github.com/dependabot/dependabot-core/pull/4714)
- Fix Running with Docker section to find the image that was just pulled (@joshuabremerdexcom) [#4694](https://github.com/dependabot/dependabot-core/pull/4694)
- build(deps): bump cython from 0.29.26 to 0.29.27 in /python/helpers [#4686](https://github.com/dependabot/dependabot-core/pull/4686)
- build(deps): bump pip-tools from 6.4.0 to 6.5.0 in /python/helpers [#4706](https://github.com/dependabot/dependabot-core/pull/4706)

## v0.171.5, 7 February 2022

- Optimize rust toolchain installation [#4711](https://github.com/dependabot/dependabot-core/pull/4711)
- Fix typo: `developerment` -> `development` (@jeffwidman) [#4705](https://github.com/dependabot/dependabot-core/pull/4705)
- Fix typo: `is does` --> `executes` (@jeffwidman) [#4704](https://github.com/dependabot/dependabot-core/pull/4704)
- Add support for Python 3.9.10 (@Dresdn) [#4692](https://github.com/dependabot/dependabot-core/pull/4692)
- Bump cargo from 1.51.0 to 1.58.0 [#4677](https://github.com/dependabot/dependabot-core/pull/4677)

## v0.171.4, 27 January 2022

- Nuget: Adding "devDependencies" support (@mwaddell) [#4671](https://github.com/dependabot/dependabot-core/pull/4671)
- Support `releases` to list of supported changelog files (@nipunn1313) [#4599](https://github.com/dependabot/dependabot-core/pull/4599)
- Composer v2: Prevent unnecessary package downloads (@driskell) [#4635](https://github.com/dependabot/dependabot-core/pull/4635)
- Python: Upgrade to 3.10.2 (@ulgens) [#4646](https://github.com/dependabot/dependabot-core/pull/4646)

## v0.171.3, 26 January 2022

- Update GitHub Actions label description [#4661](https://github.com/dependabot/dependabot-core/pull/4661)
- build(deps): bump hashin from 0.15.0 to 0.17.0 in /python/helpers [#4619](https://github.com/dependabot/dependabot-core/pull/4619)
- build(deps): bump lodash from 4.17.20 to 4.17.21 in /npm_and_yarn/helpers/test/yarn/fixtures/conflicting-dependency-parser/deeply-nested [#4668](https://github.com/dependabot/dependabot-core/pull/4668)
- build(deps): bump extend from 3.0.0 to 3.0.2 in /npm_and_yarn/helpers/test/npm6/fixtures/conflicting-dependency-parser/simple [#4667](https://github.com/dependabot/dependabot-core/pull/4667)
- build(deps-dev): bump eslint from 8.6.0 to 8.7.0 in /npm_and_yarn/helpers [#4637](https://github.com/dependabot/dependabot-core/pull/4637)
- build(deps-dev): bump phpstan/phpstan from 1.3.3 to 1.4.2 in /composer/helpers/v2 [#4644](https://github.com/dependabot/dependabot-core/pull/4644)
- build(deps-dev): bump phpstan/phpstan from 1.3.3 to 1.4.2 in /composer/helpers/v1 [#4645](https://github.com/dependabot/dependabot-core/pull/4645)
- build(deps): bump npm from 6.14.14 to 6.14.16 in /npm_and_yarn/helpers [#4651](https://github.com/dependabot/dependabot-core/pull/4651)
- build(deps): bump @npmcli/arborist from 4.1.1 to 4.2.1 in /npm_and_yarn/helpers [#4655](https://github.com/dependabot/dependabot-core/pull/4655)
- build(deps): bump composer/composer from 2.2.4 to 2.2.5 in /composer/helpers/v2 [#4657](https://github.com/dependabot/dependabot-core/pull/4657)
- build(deps): bump composer/composer from 1.10.24 to 1.10.25 in /composer/helpers/v1 [#4658](https://github.com/dependabot/dependabot-core/pull/4658)
- npm7: Fix subdependency versoion resolver [#4664](https://github.com/dependabot/dependabot-core/pull/4664)
- Add section to debug native helper scripts [#4665](https://github.com/dependabot/dependabot-core/pull/4665)
- Bitbucket: creating pull-request-creator fails on labeler not supporting bitbucket (@stefangr) [#4608](https://github.com/dependabot/dependabot-core/pull/4608)

## v0.171.2, 14 January 2022

- Support npm lockfile v3 format [#4630](https://github.com/dependabot/dependabot-core/pull/4630)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.3.2 to 3.4.0 in /composer/helpers/v2 [#4516](https://github.com/dependabot/dependabot-core/pull/4516)
- Terraform unknown git repo dependency name (@dwc0011) [#4493](https://github.com/dependabot/dependabot-core/pull/4493)
- build(deps-dev): bump jest from 27.4.5 to 27.4.7 in /npm_and_yarn/helpers [#4594](https://github.com/dependabot/dependabot-core/pull/4594)
- build(deps-dev): bump eslint from 8.5.0 to 8.6.0 in /npm_and_yarn/helpers [#4577](https://github.com/dependabot/dependabot-core/pull/4577)
- build(deps): bump jason from 1.2.2 to 1.3.0 in /hex/helpers [#4557](https://github.com/dependabot/dependabot-core/pull/4557)

## v0.171.1, 12 January 2022

- build(deps): bump composer/composer from 1.10.23 to 1.10.24 in /composer/helpers/v1 [#4509](https://github.com/dependabot/dependabot-core/pull/4509)
- build(deps-dev): bump phpstan/phpstan from 1.3.1 to 1.3.3 in /composer/helpers/v1 [#4613](https://github.com/dependabot/dependabot-core/pull/4613)
- build(deps-dev): bump phpstan/phpstan from 1.3.1 to 1.3.3 in /composer/helpers/v2 [#4612](https://github.com/dependabot/dependabot-core/pull/4612)
- Refresh the workflow for native helpers within the docker dev shell, Consistency pass on native dev [#4556](https://github.com/dependabot/dependabot-core/pull/4556)
- build(deps): bump composer/composer from 2.1.14 to 2.2.4 in /composer/helpers/v2 [#4611](https://github.com/dependabot/dependabot-core/pull/4611)

## v0.171.0, 11 January 2022

- Consistency pass on composer native helper build [#4554](https://github.com/dependabot/dependabot-core/pull/4554)
  - NOTE: If you are using the `dependabot-composer` gem in your Dependabot scripts, you must ensure you upgrade
    both the gem and the `dependabot/dependabot-core` image to v0.171.0 at the same time as this change modifies the
    install path for composer's native helpers in both.

## v0.170.2, 11 January 2022

- build(deps): bump pipenv from 2021.11.23 to 2022.1.8 in /python/helpers [#4609](https://github.com/dependabot/dependabot-core/pull/4609)

## v0.170.1, 10 January 2022

- Ensure CI builds pick up native helper changes [#4618](https://github.com/dependabot/dependabot-core/pull/4618)
- Fix poetry secondary source bug (@isobelhooper) [#4323](https://github.com/dependabot/dependabot-core/pull/4323)
- build(deps-dev): bump phpstan/phpstan from 1.2.0 to 1.3.1 in /composer/helpers/v2 [#4583](https://github.com/dependabot/dependabot-core/pull/4583)
- Ensure CI uses the latest image built on that branch [#4596](https://github.com/dependabot/dependabot-core/pull/4596)

## v0.170.0, 5 January 2022

- Allow configuration of GOPRIVATE [#4568](https://github.com/dependabot/dependabot-core/pull/4568)
- build(deps-dev): bump phpstan/phpstan from 1.2.0 to 1.3.1 in /composer/helpers/v1 [#4582](https://github.com/dependabot/dependabot-core/pull/4582)
- Simplify Dockerfile a little bit (@PeterDaveHello) [#4584](https://github.com/dependabot/dependabot-core/pull/4584)
- Check for access before ghcr push [#4569](https://github.com/dependabot/dependabot-core/pull/4569)
- Cleanup after byebug removal [#4567](https://github.com/dependabot/dependabot-core/pull/4567)
- build(deps): bump cython from 0.29.25 to 0.29.26 in /python/helpers [#4540](https://github.com/dependabot/dependabot-core/pull/4540)
- build(deps): bump wheel from 0.37.0 to 0.37.1 in /python/helpers [#4562](https://github.com/dependabot/dependabot-core/pull/4562)
- Enable support for ActiveSupport 7 [#4559](https://github.com/dependabot/dependabot-core/pull/4559)
- Python: Move some more tests to the slow suite [#4564](https://github.com/dependabot/dependabot-core/pull/4564)
- Use GHCR as the canonical source for CI images [#4560](https://github.com/dependabot/dependabot-core/pull/4560)
- Python: Quarantine slow tests into their own CI run [#4558](https://github.com/dependabot/dependabot-core/pull/4558)
- Update the CI workflow to use GHPR for branch images and as a mirror for CI images [#4524](https://github.com/dependabot/dependabot-core/pull/4524)

## v0.169.8, 21 December 2021

- Bundler: update bundler to 2.2.33 [#4534](https://github.com/dependabot/dependabot-core/pull/4534)
- Bundler: Fix syntax for setting bundle config [#4552](https://github.com/dependabot/dependabot-core/pull/4552)
- Common: Consider all failed requests to check enterprise source as false [#4551](https://github.com/dependabot/dependabot-core/pull/4551)
- build(deps-dev): bump eslint from 8.4.1 to 8.5.0 in /npm_and_yarn/helpers [#4547](https://github.com/dependabot/dependabot-core/pull/4547)

## v0.169.7, 19 December 2021

- Common: Constrain activesupport to < 7 [#4541](https://github.com/dependabot/dependabot-core/pull/4541)
- Dev: Avoid setting HTTP_PROXY for docker in the dev shell [#4533](https://github.com/dependabot/dependabot-core/pull/4533)
- Python: Upgrade pyenv to 2.2.2 (@Dresdn) [#4526](https://github.com/dependabot/dependabot-core/pull/4526)
- Cargo: Allow whitespace at beginning of Cargo dependency declarations [#4528](https://github.com/dependabot/dependabot-core/pull/4528)
- Terraform: Return name unless contains git dependency name notation (@dwc0011) [#4527](https://github.com/dependabot/dependabot-core/pull/4527)
- Dev: Fix conditional in `docker` workflow [#4529](https://github.com/dependabot/dependabot-core/pull/4529)
- Dev: build(deps-dev): bump jest from 27.4.3 to 27.4.5 in /npm_and_yarn/helpers [#4522](https://github.com/dependabot/dependabot-core/pull/4522)
- Dev: Disable `docker` workflow on forks [#4525](https://github.com/dependabot/dependabot-core/pull/4525)
- Dev: Push dependabot/dependabot-core to GHCR in order to provide a mirror [#4523](https://github.com/dependabot/dependabot-core/pull/4523)
- Dev: Reinstate the dev container build, pushing to GHCR [#4517](https://github.com/dependabot/dependabot-core/pull/4517)

## v0.169.6, 13 December 2021

- Python invalid url [#4514](https://github.com/dependabot/dependabot-core/pull/4514)
- Fix failing Cargo test [#4520](https://github.com/dependabot/dependabot-core/pull/4520)
- Bump go from 1.17.4 to 1.17.5 [#4512](https://github.com/dependabot/dependabot-core/pull/4512)
- Remove the developer image docker build [#4513](https://github.com/dependabot/dependabot-core/pull/4513)
- Prebuild and publish the dependabot/dependabot-core-development container [#4511](https://github.com/dependabot/dependabot-core/pull/4511)
- build(deps): bump composer/composer from 2.1.12 to 2.1.14 in /composer/helpers/v2 [#4473](https://github.com/dependabot/dependabot-core/pull/4473)

## v0.169.5, 9 December 2021

- build(deps): bump @npmcli/arborist from 4.0.5 to 4.1.1 in /npm_and_yarn/helpers [#4505](https://github.com/dependabot/dependabot-core/pull/4505)
- build(deps-dev): update rubocop requirement from ~> 1.18.0 to ~> 1.23.0 in /common [#4413](https://github.com/dependabot/dependabot-core/pull/4413)
- Autofix all rubocop lint [#4499](https://github.com/dependabot/dependabot-core/pull/4499)
- build(deps-dev): bump jest from 27.2.5 to 27.4.3 in /npm_and_yarn/helpers [#4478](https://github.com/dependabot/dependabot-core/pull/4478)
- feat(:git): do not decline valid git@... source (@sebbrandt87) [#4490](https://github.com/dependabot/dependabot-core/pull/4490)
- build(deps-dev): bump prettier from 2.4.1 to 2.5.1 in /npm_and_yarn/helpers [#4489](https://github.com/dependabot/dependabot-core/pull/4489)
- build(deps-dev): bump eslint from 8.3.0 to 8.4.1 in /npm_and_yarn/helpers [#4494](https://github.com/dependabot/dependabot-core/pull/4494)
- build(deps): bump cython from 0.29.24 to 0.29.25 in /python/helpers [#4495](https://github.com/dependabot/dependabot-core/pull/4495)
- Bump to go 1.17.4 (@jeffwidman) [#4492](https://github.com/dependabot/dependabot-core/pull/4492)

## v0.169.4, 7 December 2021

- Maven: Handle nested plugin declarations [#4487](https://github.com/dependabot/dependabot-core/pull/4487)

## v0.169.3, 2 December 2021

- Test for updating version of a parent pom [#4477](https://github.com/dependabot/dependabot-core/pull/4477)
- Revert "Maven: Correctly handle nested declarations" [#4479](https://github.com/dependabot/dependabot-core/pull/4479)
- Fix terraform dependency checker (@dwc0011) [#4440](https://github.com/dependabot/dependabot-core/pull/4440)
- Add tech-debt issue template (@jeffwidman) [#4470](https://github.com/dependabot/dependabot-core/pull/4470)
- Add bundler/helpers directory to devcontainer.json for VSCode (@dwc0011) [#4471](https://github.com/dependabot/dependabot-core/pull/4471)
- Limit the GitHub PR description message to API max [#4450](https://github.com/dependabot/dependabot-core/pull/4450)

## v0.169.2, 30 November 2021

- Hex: Handle additional dynamic version reading approaches [#4442](https://github.com/dependabot/dependabot-core/pull/4442)
- Update contributor from Dependabot Ltd to GitHub Inc (@jjcaine) [#4463](https://github.com/dependabot/dependabot-core/pull/4463)
- Bump Terraform from 1.0.8 to 1.0.11 [#4464](https://github.com/dependabot/dependabot-core/pull/4464)
- Introduce dependabot-fixture for npm6 unpinned git source test [#4466](https://github.com/dependabot/dependabot-core/pull/4466)

## v0.169.1, 29 November 2021

- build(deps): bump poetry from 1.1.11 to 1.1.12 in /python/helpers [#4461](https://github.com/dependabot/dependabot-core/pull/4461)
- build(deps): bump composer/composer from 2.1.9 to 2.1.12 in /composer/helpers/v2 [#4395](https://github.com/dependabot/dependabot-core/pull/4395)
- build(deps-dev): bump phpstan/phpstan from 0.12.93 to 1.2.0 in /composer/helpers/v2 [#4431](https://github.com/dependabot/dependabot-core/pull/4431)
- build(deps-dev): bump phpstan/phpstan from 0.12.99 to 1.2.0 in /composer/helpers/v1 [#4430](https://github.com/dependabot/dependabot-core/pull/4430)
- build(deps-dev): bump eslint from 8.0.0 to 8.3.0 in /npm_and_yarn/helpers [#4436](https://github.com/dependabot/dependabot-core/pull/4436)
- build(deps): bump pipenv from 2021.11.15 to 2021.11.23 in /python/helpers [#4452](https://github.com/dependabot/dependabot-core/pull/4452)
- Go modules: Bump minimum to 1.17 (@jeffwidman) [#4447](https://github.com/dependabot/dependabot-core/pull/4447)

## v0.169.0, 23 November 2021

- Use `go list -m -versions` to determine available versions of a go module [#4434](https://github.com/dependabot/dependabot-core/pull/4434)
- python: Upgrade to pip 21.3.1 (@rouge8) [#4444](https://github.com/dependabot/dependabot-core/pull/4444)

## v0.168.0, 23 November 2021

- [Azure] Check & Raise TagsCreationForbidden Exception (@AlekhyaYalla) [#4352](https://github.com/dependabot/dependabot-core/pull/4352)
- Use redirect.github.com for redirect service [#4441](https://github.com/dependabot/dependabot-core/pull/4441)
- Python: Honour `--strip-extras` flag of `pip-compile` (@NicolasT) [#4439](https://github.com/dependabot/dependabot-core/pull/4439)
- build(deps): bump pipenv from 2021.5.29 to 2021.11.15 in /python/helpers [#4408](https://github.com/dependabot/dependabot-core/pull/4408)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 2.19.2 to 2.19.3 in /composer/helpers/v1 [#4415](https://github.com/dependabot/dependabot-core/pull/4415)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.2.1 to 3.3.2 in /composer/helpers/v2 [#4414](https://github.com/dependabot/dependabot-core/pull/4414)
- Run YarnUpdate only once for a version requirement (@AlekhyaYalla) [#4409](https://github.com/dependabot/dependabot-core/pull/4409)
- Do not freeze file-based Poetry dependency version (@phillipuniverse) [#4334](https://github.com/dependabot/dependabot-core/pull/4334)
- Remove reliance on `PandocRuby` [#4433](https://github.com/dependabot/dependabot-core/pull/4433)
- build(deps): bump @npmcli/arborist from 3.0.0 to 4.0.5 in /npm_and_yarn/helpers [#4429](https://github.com/dependabot/dependabot-core/pull/4429)
- Add support for custom commit message trailers (@andrcuns) [#4432](https://github.com/dependabot/dependabot-core/pull/4432)
- Support updating dependencies on settings file (@anatawa12) [#4374](https://github.com/dependabot/dependabot-core/pull/4374)
- Remove the dependabot migration issue template [#4422](https://github.com/dependabot/dependabot-core/pull/4422)

## v0.167.0, 16 November 2021

- Maven: Correctly handle nested declarations [#4417](https://github.com/dependabot/dependabot-core/pull/4417)
- Add parsing of MSBuild SDK dependencies (NuGet) (@Zastai) [#2849](https://github.com/dependabot/dependabot-core/pull/2849)
- fix: remove fixed error message check [#4412](https://github.com/dependabot/dependabot-core/pull/4412)

## v0.166.1, 12 November 2021

- Terraform: Improve file updater and registry request error handling [#4405](https://github.com/dependabot/dependabot-core/pull/4405)
- Explicitly ignore metadata detection for fuchsia.googlesource.com [#4402](https://github.com/dependabot/dependabot-core/pull/4402)

## v0.166.0, 11 November 2021

- Ignore errors from Source enterprise check and ignore known failures [#4401](https://github.com/dependabot/dependabot-core/pull/4401)
- Bump to go 1.17.3 (@jeffwidman) [#4393](https://github.com/dependabot/dependabot-core/pull/4393)
- Move composer-not-found fixture from decommissioned dependabot.com [#4399](https://github.com/dependabot/dependabot-core/pull/4399)

## v0.165.0, 8 November 2021

- Add timeout per operation [#4362](https://github.com/dependabot/dependabot-core/pull/4362)

## v0.164.1, 2 November 2021

- Only check auth for github.com when running `bump-version` [#4347](https://github.com/dependabot/dependabot-core/pull/4347)
- Ensure we cleanup tmp directories after use [#4356](https://github.com/dependabot/dependabot-core/pull/4356)
- Treat GHES hosted sources as github sources [#4335](https://github.com/dependabot/dependabot-core/pull/4335)

## v0.164.0, 27 October 2021

- Add license to image and gemspec [#4317](https://github.com/dependabot/dependabot-core/pull/4317)
- Gitlab: add support for creating merge requests for forks (@andrcuns) [#4324](https://github.com/dependabot/dependabot-core/pull/4324)
- update Elixir from 1.12.2 -> 1.12.3 (@baseballlover723) [#4250](https://github.com/dependabot/dependabot-core/pull/4250)
- build(deps): bump flake8 from 4.0.0 to 4.0.1 in /python/helpers [#4308](https://github.com/dependabot/dependabot-core/pull/4308)
- Bump Terraform from 1.0.6 to 1.0.8 [#4310](https://github.com/dependabot/dependabot-core/pull/4310)
- build(deps): bump pip-tools from 6.3.1 to 6.4.0 in /python/helpers [#4312](https://github.com/dependabot/dependabot-core/pull/4312)
- Python: Upgrade pyenv to 2.1.0 (@Parnassius) [#4307](https://github.com/dependabot/dependabot-core/pull/4307)
- Upgrade OTP to latest minor: 23.3.4.5 (@tomaspinho) [#4306](https://github.com/dependabot/dependabot-core/pull/4306)
- hex: handle support files with macro in umbrellas (@nirev) [#4213](https://github.com/dependabot/dependabot-core/pull/4213)
- Describe workaround for cloning with long file names on Windows (@Marcono1234) [#4198](https://github.com/dependabot/dependabot-core/pull/4198)
- build(deps): bump golang.org/x/mod from 0.5.0 to 0.5.1 in /go_modules/helpers [#4254](https://github.com/dependabot/dependabot-core/pull/4254)
- build(deps): bump pip from 21.1.3 to 21.2.4 in /python/helpers [#4136](https://github.com/dependabot/dependabot-core/pull/4136)
- build(deps-dev): bump eslint from 7.32.0 to 8.0.0 in /npm_and_yarn/helpers [#4301](https://github.com/dependabot/dependabot-core/pull/4301)
- build(deps): bump flake8 from 3.9.2 to 4.0.0 in /python/helpers [#4303](https://github.com/dependabot/dependabot-core/pull/4303)
- build(deps-dev): bump jest from 27.2.4 to 27.2.5 in /npm_and_yarn/helpers [#4304](https://github.com/dependabot/dependabot-core/pull/4304)
- build(deps): bump pip-tools from 6.3.0 to 6.3.1 in /python/helpers [#4302](https://github.com/dependabot/dependabot-core/pull/4302)
- Clarify that Remote Containers Clone Repository commands are not supported (@Marcono1234) [#4199](https://github.com/dependabot/dependabot-core/pull/4199)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 2.19.0 to 2.19.2 in /composer/helpers/v1 [#4152](https://github.com/dependabot/dependabot-core/pull/4152)
- build(deps): bump wheel from 0.36.2 to 0.37.0 in /python/helpers [#4128](https://github.com/dependabot/dependabot-core/pull/4128)
- build(deps-dev): bump prettier from 2.3.2 to 2.4.1 in /npm_and_yarn/helpers [#4233](https://github.com/dependabot/dependabot-core/pull/4233)

## v0.163.0, 7 October 2021

- build(deps): bump composer/composer from 2.1.3 to 2.1.9 in /composer/helpers/v2 [#4286](https://github.com/dependabot/dependabot-core/pull/4286)
- Bitbucket: Fix unsupported labels error (@meladRaouf) [#4236](https://github.com/dependabot/dependabot-core/pull/4236)
- build(deps): bump pip-tools from 6.2.0 to 6.3.0 in /python/helpers [#4251](https://github.com/dependabot/dependabot-core/pull)
- build(deps): bump poetry from 1.1.7 to 1.1.11 in /python/helpers [#4281](https://github.com/dependabot/dependabot-core/pull/4281)
- build(deps-dev): bump jest from 27.0.6 to 27.2.4 in /npm_and_yarn/helpers [#4271](https://github.com/dependabot/dependabot-core/pull/4271)
- Poetry: Fix unreachable git deps error [#4295](https://github.com/dependabot/dependabot-core/pull/4295)
- Elm: Fix failing tests [#4294](https://github.com/dependabot/dependabot-core/pull/4294)
- build(deps-dev): bump friendsofphp/php-cs-fixer from 3.0.0 to 3.2.1 in /composer/helpers/v2 [#4285](https://github.com/dependabot/dependabot-core/pull/4285)
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers [#4284](https://github.com/dependabot/dependabot-core/pull/4284)
- build(deps): bump composer/composer from 1.10.22 to 1.10.23 in /composer/helpers/v1 [#4283](https://github.com/dependabot/dependabot-core/pull/4283)
- npm: Handle .tar path dependency (@AlekhyaYalla) [#4246](https://github.com/dependabot/dependabot-core/pull/4246)
- build(deps-dev): bump jest in /npm_and_yarn/helpers [#4271](https://github.com/dependabot/dependabot-core/pull/4271)
- Gradle: Add support for `gradlePluginPortal()` (@zbynek) [#4268](https://github.com/dependabot/dependabot-core/pull/4268)
- Gradle: Support Gradle files with no top level build.gradle file (@zbynek) [#4256](https://github.com/dependabot/dependabot-core/pull/4256)

## v0.162.2, 29 September 2021

- Ignore replaced dependencies in go.mod (@jerbob92) [#4140](https://github.com/dependabot/dependabot-core/pull/4140)
- Treat hyphens and underscores the same in Gradle versioning (@zbynek) [#4257](https://github.com/dependabot/dependabot-core/pull/4257)

## v0.162.1, 20 September 2021

- Fix minor typos in changelog (@zbynek) [#4237](https://github.com/dependabot/dependabot-core/pull/4237)
- Bump golang from 1.17 to 1.17.1 [#4231](https://github.com/dependabot/dependabot-core/pull/4231)
- build(deps): bump github.com/dependabot/gomodules-extracted from 1.4.1 to 1.4.2 in /go_modules/helpers [#4235](https://github.com/dependabot/dependabot-core/pull/4235)
- Improved support `apply from` in gradle files (@zbynek) [#4155](https://github.com/dependabot/dependabot-core/pull/4155)
- Escape paths passed to VendorUpdater [#4221](https://github.com/dependabot/dependabot-core/pull/4221)
- bin/dry-run.rb requires a development container to run [#4215](https://github.com/dependabot/dependabot-core/pull/4215)
- Python: Upgrade pyenv to 2.0.6 (@pauloromeira) [#4207](https://github.com/dependabot/dependabot-core/pull/4207)
- handle terraform module versions with a 'v' prefix (@declan-fitzpatrick) [#4191](https://github.com/dependabot/dependabot-core/pull/4191)

## v0.162.0, 7 September 2021

- Python: Raise resolvability error with explanation when update is not possible [#4206](https://github.com/dependabot/dependabot-core/pull/4206)
- chore: run builds on a regular basis to detect anomalies [#4185](https://github.com/dependabot/dependabot-core/pull/4185)
- fix: Parse multiple requirements from a poetry dependency [#4179](https://github.com/dependabot/dependabot-core/pull/4179)
- Bump terraform CLI from 1.0.0 to 1.0.6 [#4205](https://github.com/dependabot/dependabot-core/pull/4205)

## v0.161.0, 1 September 2021

- Upgrade npm to 7.21.0
- Pin Faraday to 1.7.0
- chore: fix typo in documentation (@rethab) [#4172](https://github.com/dependabot/dependabot-core/pull/4172)
- build(deps): update commonmarker requirement from >= 0.20.1, < 0.23.0 to >= 0.20.1, < 0.24.0

## v0.160.1, 25 August 2021

- build(deps): bump github.com/dependabot/gomodules-extracted from 1.3.0 to 1.4.1 in /go_modules/helpers [#4157](https://github.com/dependabot/dependabot-core/pull/4157)
- Add a minimal test for go 1.17 module handling [#4159](https://github.com/dependabot/dependabot-core/pull/4159)
- Bump bundler from 2.2.20 to 2.2.25 [#4132](https://github.com/dependabot/dependabot-core/pull/4132)

## v0.160.0, 18 August 2021

- Bump go from 1.16.7 to 1.17 (@obalunenko) [#4149](https://github.com/dependabot/dependabot-core/pull/4149)
- build(deps): bump golang.org/x/mod from 0.4.2 to 0.5.0 in /go_modules/helpers [#4139](https://github.com/dependabot/dependabot-core/pull/4139)

## v0.159.2, 17 August 2021

- Bump go from 1.16.3 to 1.16.7 [#4145](https://github.com/dependabot/dependabot-core/pull/4145)
- Handle unreachable go module dependencies in LatestVersionFinder [#4142](https://github.com/dependabot/dependabot-core/pull/4142)
- Fix failing go modules tests [#4141](https://github.com/dependabot/dependabot-core/pull/4141)

## v0.159.1, 12 August 2021

- gomod: Handle errors where go module dependencies are unreachable [#4130](https://github.com/dependabot/dependabot-core/pull/4130)

## v0.159.0, 4 August 2021

- Remove go dep entirely (@jeffwidman) [#3538](https://github.com/dependabot/dependabot-core/pull/3538)
- Skip classifier when checking for internal dep (@honnix) [#4117](https://github.com/dependabot/dependabot-core/pull/4117)
- Improve argument sanitation [#4121](https://github.com/dependabot/dependabot-core/pull/4121)

## v0.158.0, 3 August 2021

- Npm: Bump npm from 7.19.1 to 7.20.3 [#4110](https://github.com/dependabot/dependabot-core/pull/4110)
- Terraform: Pin fixture to range to prevent tests failing [#4115](https://github.com/dependabot/dependabot-core/pull/4115)
- build(deps-dev): bump eslint from 7.31.0 to 7.32.0 in /npm_and_yarn/helpers [#4112](https://github.com/dependabot/dependabot-core/pull/4112)
- build(deps): bump @npmcli/arborist from 2.7.1 to 2.8.0 in /npm_and_yarn/helpers [#4098](https://github.com/dependabot/dependabot-core/pull/4098)
- build(deps): bump npm from 6.14.13 to 6.14.14 in /npm_and_yarn/helpers [#4099](https://github.com/dependabot/dependabot-core/pull/4099)

## v0.157.2, 28 July 2021

- fix(terraform): exclude path source types in update check [#4097](https://github.com/dependabot/dependabot-core/pull/4097)
- Document pinned OTP version [#4092](https://github.com/dependabot/dependabot-core/pull/4092)

## v0.157.1, 27 July 2021

- Upgrade elixir to v1.12.2 [#4093](https://github.com/dependabot/dependabot-core/pull/4093)
- Revert "Elixir version upgrades" [#4091](https://github.com/dependabot/dependabot-core/pull/4091)

## v0.157.0, 26 July 2021

- Elixir version upgrades (@baseballlover723) [#4089](https://github.com/dependabot/dependabot-core/pull/4089)

## v0.156.10, 26 July 2021
- Make native-mt and agp version types for Maven and Gradle (@greysteil) [#4077](https://github.com/dependabot/dependabot-core/pull/4077)
- Python: Upgrade pyenv to 2.0.4 [#4086](https://github.com/dependabot/dependabot-core/pull/4086)
- build(deps-dev): bump phpstan/phpstan from 0.12.92 to 0.12.93 in /composer/helpers/v2 [#4067](https://github.com/dependabot/dependabot-core/pull/4067)
- build(deps-dev): bump phpstan/phpstan from 0.12.92 to 0.12.93 in /composer/helpers/v1 [#4068](https://github.com/dependabot/dependabot-core/pull/4068)

## v0.156.9, 20 July 2021

- build(deps): bump @npmcli/arborist from 2.7.0 to 2.7.1 in /npm_and_yarn/helpers [#4055](https://github.com/dependabot/dependabot-core/pull/4055)
- build(deps-dev): bump eslint from 7.30.0 to 7.31.0 in /npm_and_yarn/helpers [#4060](https://github.com/dependabot/dependabot-core/pull/4060)
- npm: prevent scoped registries becoming global [#4061](https://github.com/dependabot/dependabot-core/pull/4061)

## v0.156.8, 15 July 2021

- Terraform: ignore symlinks in file fetcher [#4053](https://github.com/dependabot/dependabot-core/pull/4053)
- Bump npm from 7.10.0 to 7.19.1 [#4052](https://github.com/dependabot/dependabot-core/pull/4052)
- Dry-run: cache cloned repos [#4050](https://github.com/dependabot/dependabot-core/pull/4050)

## v0.156.7, 15 July 2021

- Terraform: support updating local path modules [#4048](https://github.com/dependabot/dependabot-core/pull/4048)
- build(deps): bump cython from 0.29.23 to 0.29.24 in /python/helpers [#4047](https://github.com/dependabot/dependabot-core/pull/4047)
- build(deps): bump @npmcli/arborist from 2.6.4 to 2.7.0 in /npm_and_yarn/helpers [#4046](https://github.com/dependabot/dependabot-core/pull/4046)

## v0.156.6, 13 July 2021

- Terraform: handle mixed case providers [#4044](https://github.com/dependabot/dependabot-core/pull/4044)

## v0.156.5, 12 July 2021

- fix(poetry): Detect relative project paths [#4018](https://github.com/dependabot/dependabot-core/pull/4018)
- Add Forbidden error type to Azure client (@wolf-cola) [#4029](https://github.com/dependabot/dependabot-core/pull/4029)
- build(deps-dev): bump phpstan/phpstan from 0.12.90 to 0.12.92 in /composer/helpers/v2 [#4036](https://github.com/dependabot/dependabot-core/pull/4036)
- build(deps-dev): bump jest from 27.0.5 to 27.0.6 in /npm_and_yarn/helpers [#4003](https://github.com/dependabot/dependabot-core/pull/4003)
- build(deps-dev): bump eslint from 7.29.0 to 7.30.0 in /npm_and_yarn/helpers [#4021](https://github.com/dependabot/dependabot-core/pull/4021)
- build(deps-dev): bump phpstan/phpstan from 0.12.90 to 0.12.92 in /composer/helpers/v1 [#4037](https://github.com/dependabot/dependabot-core/pull/4037)
- Gomod: Handle unrecognized import path error [#4016](https://github.com/dependabot/dependabot-core/pull/4016)
- Fix for Azure client trying to parse 401 responses (@wolf-cola) [#4012](https://github.com/dependabot/dependabot-core/pull/4012)

## v0.156.4, 30 June 2021

- build(deps): bump @npmcli/arborist from 2.6.3 to 2.6.4 in /npm_and_yarn/helpers [#3988](https://github.com/dependabot/dependabot-core/pull/3988)
- build(deps-dev): update rubocop requirement from ~> 1.17.0 to ~> 1.18.0 in /common [#4004](https://github.com/dependabot/dependabot-core/pull/4004)
- fix(Maven): Add support for updating Maven extensions.xml files (@britter) [#3366](https://github.com/dependabot/dependabot-core/pull/3366)

## v0.156.3, 29 June 2021

- Python: bump poetry from 1.1.6 to 1.1.7 in /python/helpers [#3996](https://github.com/dependabot/dependabot-core/pull/3996)
- Python: bump pip from 21.1.2 to 21.1.3 in /python/helpers [#3997](https://github.com/dependabot/dependabot-core/pull/3997)
- PR Updater: Handle required status checks [#3998](https://github.com/dependabot/dependabot-core/pull/3998)

## v0.156.2, 25 June 2021

- poetry: skip path and url dependencies [#3991](https://github.com/dependabot/dependabot-core/pull/3991)
- Terraform: Prevent `terraform init` from initializing backends (@hfurubotten) [#3986](https://github.com/dependabot/dependabot-core/pull/3986)

## v0.156.1, 24 June 2021

- Terraform: Configure git for `terraform init` and capture errors [#3983](https://github.com/dependabot/dependabot-core/pull/3983)
- build(deps-dev): update rubocop requirement from ~> 1.16.0 to ~> 1.17.0 in /common [#3912](https://github.com/dependabot/dependabot-core/pull/3912)

## v0.156.0, 23 June 2021

- Create changelog from merge commits [#3642](https://github.com/dependabot/dependabot-core/pull/3642)
- Terraform: always clone repository contents [#3978](https://github.com/dependabot/dependabot-core/pull/3978)
- build(deps): bump pip-tools from 6.1.0 to 6.2.0 in /python/helpers [#3974](https://github.com/dependabot/dependabot-core/pull/3974)
- Hex: Adds support for sub-projects without the need for umbrella applications (@gjsduarte) [#3944](https://github.com/dependabot/dependabot-core/pull/3944)

## v0.155.1, 23 June 2021

- Terraform: fix module updates with a lockfile
- nuget: handle RepositoryDetails without BaseAddress
- bundler: GemspecSanitizer replace interpolated strings
- build(deps-dev): bump jest in /npm_and_yarn/helpers

## v0.155.0, 22 June 2021

- Go: add security advisories
- Devcontainer: do not rename gemspec
- docker-dev-shell: do not rename gemspec

## v0.154.5, 22 June 2021

- Terraform: install modules when updating lockfile

## v0.154.4, 22 June 2021

- Terraform: handle nested module sources
- Common: refactor filter_vulnerable_version into a separate module
- Bundler: ignore invalid auth_uri

## v0.154.3, 21 June 2021

- Terraform: handle missing source
- Terraform: handle unreachable private module proxy
- Terraform: handle dependencies without a namespace
- fix: Fetches upload-pack using git if http fails
- chore: shellcheck scripts
- chore: Replace wget with curl @PeterDaveHello
- chore: Double quote shell variables in Dockerfile @PeterDaveHello
- Returns basename and relative path in CodeCommit file fetcher @lorengordon
- build(deps-dev): bump phpstan/phpstan in /composer/helpers/v1 and /composer/helpers/v2
- build(deps): update commonmarker requirement from >= 0.20.1, < 0.22.0 to >= 0.20.1, < 0.23.0
- build(deps-dev): bump eslint in /npm_and_yarn/helpers
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers

## v0.154.2, 17 June 2021

- Terraform: Handle 401 registry responses
- GitHub actions: Handle no latest version found
- Python: Fix ruby 2.7 deprecations
- Double quote variables in shellscript @PeterDaveHello
- Add `--no-install-recommends` to all `apt-get install` in Dockerfile @PeterDaveHello

## v0.154.1, 16 June 2021

- Ruby: Fix 2.7 deprecation warnings in rubygems
- Bundler: Run native helper specs

## v0.154.0, 15 June 2021

- Update ruby from 2.6 to 2.7
- Bundler: add missing specs from bundler1 and load bundler2 fixtures
- Dockerfile improvements @PeterDaveHello
  - Set SHELL option for shell pipe
  - Add missing `-y` for apt-get install
  - Fix npm cache clean up
  - Add missing apt lists clean up

## v0.153.0, 14 June 2021

- Bundler: Upgrade rubygems to 3.2.20 and bundler to 2.2.20
- Python: Upgrade pyenv to 2.0.1 to add support for Python 3.9.5
- build(deps-dev): bump phpstan/phpstan in /composer/helpers/v1
- build(deps-dev): bump phpstan/phpstan in /composer/helpers/v2
- build(deps): bump composer/composer in /composer/helpers/v2

## v0.152.1, 11 June 2021

- Tests: Allow profiling tests with stackprof when tagged
- Throw an error when using the deprecated terraform provider syntax, include upgrade instructions
- Update `bump-version` with instructions to checkout the new branch

## v0.152.0, 10 June 2021

- Python: Upgrade pip to 21.1.2
- Python: Upgrade pip-tools to 6.1.0
- Python: Drop python 2.x support
- Python: Upgrade pipenv to 2021.5.29
- Terraform: Add support for lockfiles
- Terraform: Upgrade and pin Terraform to version 1.0.0

## v0.151.1, 7 June 2021

fix(npm): Prevent unnecessary hash pinning in lock file constraint

## v0.151.0, 7 June 2021

- Pin erlang to OTP 23 until we can resolve OTP 24 warning issues
- build(deps-dev): bump friendsofphp/php-cs-fixer in /composer/helpers/v2

## v0.150.0, 7 June 2021

- build(deps): bump composer/composer from 2.0.14 to 2.1.1 in /composer/helpers/v2
- build(deps-dev): bump jest in /npm_and_yarn/helpers
- build(deps-dev): bump eslint in /npm_and_yarn/helpers
- build(deps-dev): bump prettier in /npm_and_yarn/helpers
- build(deps): bump dependabot/fetch-metadata from 1.0.2 to 1.0.3
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers

## v0.149.5, 2 June 2021

- build(deps): bump detect-indent in /npm_and_yarn/helpers
- chore(deps): bump composer/composer in /composer/helpers/v2
- chore(deps-dev): update rubocop requirement from ~> 1.15.0 to ~> 1.16.0
- refactor(Terraform): raise PrivateSourceAuthenticationFailure instead of DependabotError
- build(deps-dev): bump jest in /npm_and_yarn/helpers
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers

## v0.149.4, 1 June 2021

- fix(Terraform): use service discovery protocol
- fix(Terraform): parse optional hostname from module/provider source address
- Bump composer/composer from 2.0.12 to 2.0.14 in /composer/helpers/v2
- poetry: support pyproject.toml indentation

## v0.149.3, 28 May 2021

- Bundler: handle required ruby version ranges in gemspecs
- Bundler: Bump to latest ruby versions
- Elixir: Bump version from 1.10.4 -> 1.11.4
- gomod: UpdateChecker - handle invalid module path error on update
- Composer: handle git clone error in lockfile updater
- Bump eslint from 7.26.0 to 7.27.0 in /npm_and_yarn/helpers

## v0.149.2, 27 May 2021

- Tests: avoid squatted repositories

## v0.149.1, 27 May 2021

- Bundler: Fix ruby version patch for 2.2.18
- Bundler: Update bundler to 2.2.18

## v0.149.0, 26 May 2021

- Terraform: Use registry credentials

## v0.148.10, 26 May 2021

- Yarn: use .yarnrc file if present
- npm: handle latest version requirement

## v0.148.9, 26 May 2021

- Terraform: Do not set dependency.version for version ranges
- Terraform: Parse lockfiles to get exact version when present

## v0.148.8, 25 May 2021

- Composer: handle unreachable git vcs source
- Terraform: handle implicit (v0.12 style) provider sources

## v0.148.7, 25 May 2021

- npm: Handle multiple sources in the update checker
- Composer: Handle invalid composer.json

## v0.148.6, 21 May 2021

- Handle nil dependency version when raising AllVersionsIgnored

## v0.148.5, 21 May 2021

- Terraform: Fix updating multiple providers
- Dockerfile: split up native helper build steps

## v0.148.4, 21 May 2021

- Terraform: Improve updating provider requirements
- Bundler 2: No longer bump yanked gems when updating dependency
- Upgrade bundler to 2.2.17
- Bump @npmcli/arborist from 2.5.0 to 2.6.0 in /npm_and_yarn/helpers

## v0.148.3, 19 May 2021

- fix(common): skip validation on non-git sources
- fix(npm/yarn): prefer private registries over public ones

## v0.148.2, 19 May 2021

- Terraform: Fix finding metadata for providers

## v0.148.1, 19 May 2021

- npm: Handle nested workspace dependencies installed in the top-level
  `node_modules` folder

## v0.148.0, 19 May 2021

- Terraform: Support provider updates
- Terraform: Extract RegistryClient for communicating with terraform registry
- Go modules: Replace custom helper with `go get -d lib@version` @jeffwidman

## v0.147.1, 18 May 2021

- Terraform: remove legacy terraform feature flag
- Terraform: Clean up support for legacy terragrunt files
- Hex: Fix version resolver specs
- Update rubocop requirement from ~> 1.14.0 to ~> 1.15.0 in /common
- Bump phpstan/phpstan from 0.12.85 to 0.12.88 in /composer/helpers/v1
- Bump phpstan/phpstan from 0.12.85 to 0.12.88 in /composer/helpers/v2
- build(deps-dev): bump eslint in /npm_and_yarn/helpers
- build(deps-dev): bump prettier in /npm_and_yarn/helpers
- build(deps): bump flake8 from 3.9.1 to 3.9.2 in /python/helpers
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers

## v0.147.0, 13 May 2021

- Switch HCL2 parser to be the default for Terraform. Supports Terraform v0.12+ [(#3716)](https://github.com/dependabot/dependabot-core/pull/3716)

## v0.146.1, 12 May 2021

- Actions: skip equivalent shorter semver tags, such as `v2` and `v2.1.0`
- Python: Run all pip-compile commands with options @JimNero009
- Terraform (prerelease): Handle terragrunt HCL files

## v0.146.0, 10 May 2021

- go_modules: Refactor go module version finder specs
- all: Filter lower versions when checking ignored versions
- Terraform: Document and improve coverage for RequirementsUpdater
- Revert "docker: FileParser consider image prefix/suffixes as unique"

## v0.145.4, 10 May 2021

- Actions: accept semver versions
- Actions: detect workflow steps pinned to semver versions

## v0.145.3, 7 May 2021

- go_modules: Gracefully handle +incompatible versions when checking for updates

## v0.145.2, 7 May 2021

- Nuget: Handle paginated v2 nuget api responses
- maven: allow security updates to multi-dependency properties
- build(deps): bump lodash
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers
- build(deps-dev): update rubocop requirement from ~> 1.13.0 to ~> 1.14.0

## v0.145.1, 5 May 2021

- go_modules: don't filter the current version
- terraform: move fixtures to project folders
## v0.145.0, 5 May 2021

- go_modules: support version ignores
- Dev env: mount go helper source in dev shell
- docker: FileParser unique suffixes
- go_modules: helper updates
- GitHub PullRequestCreator: prepend refs/
- build(deps): bump github.com/dependabot/gomodules-extracted

## v0.144.0, 5 May 2021

- Elm: Drop support for Elm 0.18
- Common: Handle nil dependency version when generating ignored versions
- Python: allow comments when parsing setup.cfg
- go_modules: stub consistently and ignore invalid modules
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers
- build(deps-dev): bump friendsofphp/php-cs-fixer in /composer/helpers/v1
- build(deps-dev): bump friendsofphp/php-cs-fixer in /composer/helpers/v2

## v0.143.6, 30 April 2021

- Common: version-update:semver-major ignores all major version updates
- Document how to run tests within the dev docker container
- go_modules: Make error output more idiomatic
- Create CODE_OF_CONDUCT.md
- Common: IgnoreCondition: handle multi-length semver ranges
- Common: IgnoreCondition: don't ignore current version when ignoring patches

## v0.143.5, 29 April 2021

- gradle: only treat commit-like versions as git repositories
- dry-run: change SECURITY_ADVISORIES to kebab-case
- go_modules: helper improvements @jeffwidman
- go_modules: require go.16 for helpers @jeffwidman
- go_modules: use go1.16.3 @jeffwidman
- docker: handle versions generated with `git describe --tags --long` @kd7lxl
- build(deps): bump composer/composer in /composer/helpers/v1
- build(deps-dev): bump phpstan/phpstan in /composer/helpers

## v0.143.4, 26 April 2021

- Common: Add IgnoreCondition.security_updates_only, which disables version updates filtering
- build(deps-dev): bump eslint-config-prettier in /npm_and_yarn/helpers
- build(deps-dev): bump eslint in /npm_and_yarn/helpers

## v0.143.3, 23 April 2021

- Common: Do not transform update_types in IgnoreCondition
- build(deps): bump @npmcli/arborist in /npm_and_yarn/helpers

## v0.143.2, 22 April 2021

- Dependabot::Config::IgnoreCondition support dependency wildcards
- Dependabot::Config::IgnoreCondition support `update-types`
- go_modules: clarify comment @jeffwidman

## v0.143.1, 21 April 2021

- Gradle/Maven: Handle ruby style requirements with maven version
- Bundler: Add missing requirement_class for bundler latest version checker
- Add IgnoreCondition#dependency_name
- Dependabot::Config::File parse ignore_conditions
- Dependabot::Config::File parse commit_message_options

## v0.143.0, 21 April 2021

- Python: Add support for updating `setup.cfg` files @honnix
- Gomod: Run `go mod tidy` with flag to allow errors
- Handle ruby and package manager specific version requirements from ignore conditions
- build(deps): bump poetry from 1.1.4 to 1.1.6 in /python/helpers
- build(deps-dev): update rubocop requirement from ~> 1.12.0 to ~> 1.13.0
- build(deps-dev): bump friendsofphp/php-cs-fixer in /composer/helpers/v1
- build(deps-dev): bump friendsofphp/php-cs-fixer in /composer/helpers/v2
- build(deps-dev): bump phpstan/phpstan in /composer/helpers/v1
- build(deps-dev): bump phpstan/phpstan in /composer/helpers/v2
- dry-run: fetch ignore conditions and commit_message_options from `dependabot.yml` config file
- dry-run: set ignore conditions from `IGNORE_CONDITIONS` env
- Chore: Refactor `new_branch_name` function in branch_namer @milind009
- Bundler: Remove unused `using_bundler2` arg from v1 helpers

## v0.142.1, 16 April 2021

- Update npm from 7.7.4 to 7.10.0
- build(deps): bump flake8 from 3.9.0 to 3.9.1 in /python/helpers
- Azure: Raise PullRequestUpdateFailed error when failing to update PR @milind009
- Fix Dockerfile.development
- build(deps): bump cython from 0.29.22 to 0.29.23 in /python/helpers

## v0.142.0, 15 April 2021

- Dockerfile: set WORKDIR to /home/dependabot to avoid permission errors when
  consumers of the dependabot-core image run bundle install @baseballlover723
- Dockerfile: Cache composer installs & install ca-certificates
- Dockerfile: shallow clone pyenv
- npm/yarn: Always use registry source when available
- build(deps-dev): bump eslint-config-prettier in /npm_and_yarn/helpers

## v0.141.1, 13 April 2021

- Remove bundler/v1/.bundle
- Remove helpers ignore
- Remove python versions from ci image and split copy
- build(deps): bump npm from 6.14.12 to 6.14.13 in /npm_and_yarn/helpers
- fix(go mod): capture module mismatch error

## v0.141.0, 12 April 2021

- Dockerfile: create a `dependabot` user and drop privileges
  This is a potentially BREAKING change for consumers of the `dependabot/dependabot-core` docker image.
- Maven/Gradle: Add option to use GitLab access token for authentication against maven repositories @gringostar
- common: raise Dependabot::OutOfDisk on more out of space errors
- Bump eslint from 7.23.0 to 7.24.0

## v0.140.3, 9 April 2021

- fix(Go mod): detect when remote end hangs up

## v0.140.2, 8 April 2021

- Go mod: Handle repo not found errors projects https://github.com/dependabot/dependabot-core/pull/3456

## v0.140.1, 8 April 2021

- Python: Disabled poetry experimental new installer @honnix
- GitLab: Implement delete/create action in client @jerbob92

## v0.140.0, 7 April 2021

- Bundler: Detecting and using the correct major Bundler version is now enabled by default
- Python: Add versions 3.8.9, 3.9.3 and 3.9.4
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v1
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v2

## v0.139.2, 6 April 2021

- Cargo: fix error when upgrading to a version with a build annotation (e.g. `0.7.0+zstd.1.4.9`)
- Maven: fix error when comparing string and integer versions
- Generate alternatives for every git source (thanks @jerbob92)
- CI: performance improvements
- Bump phpstan/phpstan from 0.12.82 to 0.12.83 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.82 to 0.12.83 in /composer/helpers/v1
- Bump composer/composer from 2.0.11 to 2.0.12 in /composer/helpers/v2
- Bump composer/composer from 1.10.20 to 1.10.21 in /composer/helpers/v1
- Bump @npmcli/arborist from 2.2.9 to 2.3.0 in /npm_and_yarn/helpers

## v0.139.1, 30 March 2021

- Pull Requests: Fix GitHub redirect for www.github.com links
- Pull Requests: Sanitize team mentions
- Bundler 2 [Beta]: Add test for bundler dependency

## v0.139.0, 30 March 2021

- Bundler [Beta]: Detect and run Bundler V1 or V2 based on Gemfile.lock
  - Requires `options: { bundler_2_available: true }` to be passed to Bundler classes for this release
- Dockerfile: promote software-properties-common

## v0.138.7, 30 March 2021

- Go mod: Handle multi-line error messages
- Bump golang.org/x/mod from 0.4.1 to 0.4.2 in /go_modules/helpers
- Update rubocop requirement from ~> 1.11.0 to ~> 1.12.0 in /common
- Bump flake8 from 3.8.4 to 3.9.0 in /python/helpers
- Bump eslint from 7.22.0 to 7.23.0 in /npm_and_yarn/helpers
- Bundler [Prerelease]: Bump bundler to 2.2.15
- Bundler: Use project fixtures
- Docs: change ci url @flaxel

## v0.138.6, 26 March 2021

- chore: export LOCAL_GITHUB_ACCESS_TOKEN to docker dev container
- fix: Raise resolvability error when pseudo version does not match version control
- test: Add a helper method to load bundler fixtures by version
- test: Explicitly raise if attempting to load a missing project fixture
- test: Project fixtures for UpdateChecker spec

## v0.138.5, 26 March 2021

- Maven/Gradle: Treat dev and pr as pre-releases for Gradle/Maven
- Bundler v2 [pre-release]: Add and test jfrog source helper
- Cargo: Update Rust to 1.51.0 (thanks @CryZe)
- Bump npm from 6.14.11 to 6.14.12 in /npm_and_yarn/helpers
- Internal: bump-version: re-tag the release notes ref
- Azure: adding azure pr updater reference in pr updater common class

## v0.138.4, 25 March 2021

- Docker: fix invalid Accept header when checking for updates
- Bundler: fix invalid requirement replacement when using `!=` filters
- Bundler [Prerelease]: Add UpdateChecker for Bundler 2
- Bundler [Prerelease]: Add version resolver for Bundler 2
- Bundler [Prerelease]: Add file updater for Bundler 2
- Dependabot::PullRequestCreator::MessageBuilder::new - github_redirection_service is a required argument
- CI: Fix flaky npm spec
- CI: Extend npm retries and max attempts
- CI: Skip coverage reports
- Update npm from 7.6.1 to 7.7.0

## v0.138.3, 24 March 2021

- Docker: Improve handling of tags with prefixes or suffixes
- Bump @npmcli/arborist from 2.2.6 to 2.2.9 in /npm_and_yarn/helpers
- Bump eslint from 7.21.0 to 7.22.0 in /npm_and_yarn/helpers
- Bundler: fix deprecated --without flag in build
- Bundler [Prerelease]: Add conflicting dependency resolver for Bundler 2
- Bundler: Avoid subtle runtime failures by raising if bundler is improperly invoked

## v0.138.2, 23 March 2021

- npm: support private registries using lowercase URI components (e.g. `%40dependabot%2fdependabot-core`)
- Bundler: [Prerelease] Add a file parser for Bundler 2
- Nuget: add support for disablePackageSources in NuGet.Config (@AshleighAdams)
- Bump phpstan/phpstan from 0.12.81 to 0.12.82
- Bump friendsofphp/php-cs-fixer to 2.18.4
- CI: reduce disk space

## v0.138.1, 17 March 2021

- Bundler: Add instrumentation to capture the bundler version being used
- Bundler: [Prerelease] Add a stubbed out native helper for Bundler 2
- Bundler: [Prerelease] Allow the v2 native helper to be invoked via an options argument

## v0.138.0, 16 March 2021

- Go: Bump golang to v1.16.2

## v0.137.2, 16 March 2021

- Bundler: Fix permission error when vendoring gems
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v1
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v2

## v0.137.1, 15 March 2021

- Bundler: Install dependabot-core's gems using Bundler v2 (unused for updates)

## v0.137.0, 15 March 2021

- Bump npm from 7.5.4 to 7.6.1
- Python: Add python versions 3.9.2, 3.8.8, 3.7.10 and 3.6.13
- Bundler: Run v1 native helpers with bundler v1
- Bump composer/composer from 2.0.10 to 2.0.11 in /composer/helpers/v2
- Bump eslint-config-prettier from 8.0.0 to 8.1.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.78 to 0.12.81 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.78 to 0.12.81 in /composer/helpers/v1

## v0.136.0, 8 March 2021

- Bundler: Run Bundler v1 native helpers with an explicit version setting the
  stage for Bundler v2 support (take 2) #3223
- Bundler: Fix gemspec sanitization bug when heredoc has methods chained onto it
  #3220

## v0.135.0, 4 March 2021

- Gracefully handle cargo version conflicts #3213
- Pull request updater for azure client #3153 (@milind009)

## v0.134.2, 3 March 2021

- Revert: Run Bundler v1 native helpers with an explicit version
- Update rubocop requirement from ~> 1.10.0 to ~> 1.11.0 in /common
- Bump @npmcli/arborist from 2.2.4 to 2.2.6 in /npm_and_yarn/helpers

## v0.134.1, 2 March 2021

- Run Bundler v1 native helpers with an explicit version setting the stage for
  Bundler v2 support

## v0.134.0, 1 March 2021

- Introduce `Dependabot::PullRequestCreator::Message` as an alternative to `Dependabot::PullRequestCreator::MessageBuilder`
- Test: convert Bundler specs to projects
- Test: fix npm6 fixture
- Bump composer/composer from 2.0.9 to 2.0.10 in /composer/helpers/v2
- Bump @npmcli/arborist from 2.2.3 to 2.2.4 in /npm_and_yarn/helpers
- Bump eslint-config-prettier from 7.2.0 to 8.0.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.77 to 0.12.78 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.77 to 0.12.78 in /composer/helpers/v1
- Bump cython from 0.29.21 to 0.29.22 in /python/helpers

## v0.133.6, 22 February 2021

- npm: Use CLI for peer dep conflicts, and default to it without lockfile
- Bump @npmcli/arborist from 2.2.2 to 2.2.3 in /npm_and_yarn/helpers

## v0.133.5, 19 February 2021

- Python: Raise UnexpectedExternalCode if `reject_external_code: true`, regardless of the update involving external code
- Hex: Raise UnexpectedExternalCode if `reject_external_code: true`, regardless of the update involving external code
- JS: fix npm file updater spec

## v0.133.4, 18 February 2021

- Elixir: support projects using Nerves extensions (@fhunleth and @cblavier)
- Common: Insert zero-width space in @mentions when sanitizing GitHub pull request descriptions
- Azure: raise NotFound error when response status code is 400 for fetch_commit (@milind009)
- JS: Switch from yarn to npm for helper deps
- JS: Convert spec fixtures to project based
- Bump phpstan/phpstan from 0.12.74 to 0.12.77 in /composer/helpers/v1
- Bump phpstan/phpstan from 0.12.76 to 0.12.77 in /composer/helpers/v2
- Update rubocop requirement from ~> 1.9.0 to ~> 1.10.0 in /common

## v0.133.3, 16 February 2021

- common: when detecting changes in vendored dependencies, assume resources are binary
- Bump phpstan/phpstan from 0.12.74 to 0.12.76 in /composer/helpers/v2
- Bump eslint from 7.19.0 to 7.20.0 in /npm_and_yarn/helpers
- Bump @npmcli/arborist from 2.2.1 to 2.2.2 in /npm_and_yarn/helpers
- Only run flake8 on python helpers folder
- Add option to profile dry-run using Stackprof
- Fix go_modules flaky spec accessing archive.org
- Restore npm6/7 yanked version spec
- npm: Convert FileParser specs to project fixtures

## v0.133.2, 11 February 2021

- Docker: Fix media types in Accept header for Docker Registry
- Convert LockfileParserSpec to use project based fixtures

## v0.133.1, 10 February 2021

- npm: fix npm 7 workspace bug when updating nested packages
- npm: correctly parse npm 7 version from package dependencies
- npm: Refactor NpmLockfileUpdater
- Update npm from 7.5.2 to 7.5.3
- Bump @npmcli/arborist from 2.2.0 to 2.2.1 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.71 to 0.12.74 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.71 to 0.12.74 in /composer/helpers/v1

## v0.133.0, 9 February 2021

- Bundler: Raise UnexpectedExternalCode if `reject_external_code: true` and the update involves external code

## v0.132.0, 8 February 2021

- npm: Add support for updating npm 7 lockfiles

## v0.131.3, 8 February 2021

- Nuget: handle version ranges in VersionFinder

## v0.131.2, 5 February 2021

- Maven: handle invalid pom references
- Maven: Raise DependencyFileNotResolvable when invalid repo is specified
- Bump @npmcli/arborist from 2.1.1 to 2.2.0 in /npm_and_yarn/helpers

## v0.131.1, 4 February 2021

- Composer: handle invalid version string
- Composer: Don't raise when adding temp platform extensions
- Composer: Handle version constraints with both caret and dev postfix
- Docker: Use the correct Docker digest when checking for updates

## v0.131.0, 4 February 2021

- Composer: handle unreachable path vcs source
- Nuget: Parse floating notation when used in range
- Nuget: Ignore `Remove` ProjectReferences
- Gradle Kotlin DSL: Add Support for Named URL Parameter in Maven Repository (@hfhbd)
- Python: Add python 3.8.7 (@Parnassius)
- npm: Refactor specs to use project based fixtures
- Bump composer/composer from 1.10.19 to 1.10.20 in /composer/helpers/v1
- Bump composer/composer from 2.0.8 to 2.0.9 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.68 to 0.12.71 in /composer/helpers/v1 and /composer/helpers/v2
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v2 and /composer/helpers/v1
- Update simplecov-console requirement from ~> 0.8.0 to ~> 0.9.1
- Bump @npmcli/arborist from 2.0.6 to 2.1.1 in /npm_and_yarn/helpers
- Update rubocop requirement from ~> 1.8.0 to ~> 1.9.0 in /common

## v0.130.3, 25 January 2021

- Extract yarn/npm lockfile updater specs from FileUpdater specs
- Bump @npmcli/arborist from 2.0.5 to 2.0.6 in /npm_and_yarn/helpers
- Gomod: go-1.15.7
- Composer: Check for explicit composer plugin version before invalid plugins
- Update eslint prettier extension
- Fix JS debugging in vscode

## v0.130.2, 19 January 2021

- gradle: repository url by assignment
- Bump pip-tools from 5.4.0 to 5.5.0
- Bump eslint from 7.17.0 to 7.18.0 in /npm_and_yarn/helpers
- Bump golang.org/x/mod from 0.4.0 to 0.4.1 in /go_modules/helpers
- Bump @npmcli/arborist from 2.0.3 to 2.0.5 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.66 to 0.12.68 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.66 to 0.12.68 in /composer/helpers/v1

## v0.130.1, 14 January 2021

- npm: detect npm v7 lockfiles
- npm: Install npm v7 (unused) alongside npm v6
- JS: Upgrade node to v14.15.4
- Common: Added require "set" to utils.rb (@JohannesEH)
- Sanitize `@mentions` by wrapping them in codeblocks preventing notifications when replying to PR email notifications

## v0.130.0, 13 January 2021

- npm: Support GitLab format npm registry (@danoe)
- npm: move native helpers to npm6 namespace
- Python: Use release version of pyenv (@ulgens)
- Gradle: Add support for Kotlin Plugins (@busches)
- Composer: Use composer v1 when any of the requirements are invalid on v2
- docker-dev-shell: exclude dry-run files
- Bump @npmcli/arborist from 2.0.2 to 2.0.3 in /npm_and_yarn/helpers
- Bump npm from 6.14.10 to 6.14.11 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.64 to 0.12.66 in /composer/helpers/v1 and /composer/helpers/v2
- Update rubocop requirement from ~> 1.7.0 to ~> 1.8.0 in /common

## v0.129.5, 7 January 2021

- Bundler: support ruby 2.7 and 3.0 version requirements in gemspecs
- Update parser requirement from ~> 2.5 to >= 2.5, < 4.0 in /common

## v0.129.4, 6 January 2021

- go_modules: raise Dependabot::GitDependenciesNotReachable for dependencies missing from github.com
- go_modules: fix regression when parsing go.mod files without dependencies
- Bitbucket: support for PR creation (@iinuwa)

## v0.129.3, 5 January 2021

- Bump eslint-plugin-prettier from 3.3.0 to 3.3.1 in /npm_and_yarn/helpers
- Gradle: Handle missing required manifest file
- Actions: Accept shortref hashes

## v0.129.2, 4 January 2021

- go_modules: return tidied `go.mod` contents directly
- go_modules: fix nested module detection from a monorepo root
- go_modules: stop parsing indirect dependencies (previous: parsed but not updated)
- gradle: fix whitespace matching in settings (@bountin)
- Add token support for BitBucket (@iinuwa)
- Add retries for Azure client (@GiriB)
- CI: Add Python flake8 linting
- Bundler: fix bundler gem when invoked as standalone gem
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v2
- Bump friendsofphp/php-cs-fixer in /composer/helpers/v1
- Bump node-notifier from 8.0.0 to 8.0.1 in /npm_and_yarn/helpers
- Update rubocop requirement from ~> 1.6.0 to ~> 1.7.0 in /common
- Update simplecov requirement from ~> 0.20.0 to ~> 0.21.0 in /common
- Bump eslint from 7.16.0 to 7.17.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.63 to 0.12.64 in /composer/helpers/v2
- Bump phpstan/phpstan from 0.12.63 to 0.12.64 in /composer/helpers/v1

## v0.129.1, 21 December 2020

- Bump phpstan/phpstan from 0.12.59 to 0.12.63
- Bump friendsofphp/php-cs-fixer
- Composer: Verify if composer name is compatible with v2
- Python: Upgrade Python version to 3.9.1 (@ulgens)
- Bump npm from 6.14.9 to 6.14.10 in /npm_and_yarn/helpers
- Bump eslint from 7.15.0 to 7.16.0 in /npm_and_yarn/helpers
- Sanitize creds from DependabotError
- Bump composer/composer from 1.10.16 to 1.10.19 in /composer/helpers/v1
- Bump pip from 20.3.1 to 20.3.3 in /python/helpers
- Bump @npmcli/arborist from 2.0.1 to 2.0.2 in /npm_and_yarn/helpers
- go_modules: limit GitDeps to repo
- go_modules: fix test warning

## v0.129.0, 15 December 2020

- Composer: Support composer v2 alongside v1 (Thanks for helping out @WyriHaximus)

## v0.128.2, 14 December 2020

- go_modules: fix regression with stubbing local replace paths

## v0.128.1, 14 December 2020

- go_modules: only stub modules outside this repo

## v0.128.0, 14 December 2020

- Gradle: Support Kotlin manifest files (thanks, @shakhar!)

## v0.127.1, 14 December 2020

- Bump wheel from 0.36.1 to 0.36.2 in /python/helpers
- Bump eslint-plugin-prettier from 3.2.0 to 3.3.0 in /npm_and_yarn/helpers
- Bump @npmcli/arborist from 2.0.0 to 2.0.1 in /npm_and_yarn/helpers

## v0.127.0, 11 December 2020

- go_modules: raise Dependabot::OutOfDisk error when we're fairly sure that the failure occurred due to running out of disk space
- Bump ini from 1.3.5 to 1.3.7 in /npm_and_yarn/helpers

## v0.126.1, 10 December 2020

- go_modules: don't raise error for `go mod tidy` executions

## v0.126.0, 8 December 2020

- pip-compile: Fix building native python dependencies
- pipenv: handle installs with missing system dependencies
- docker: support platform option in from line @ttshivers
- Bump pip from 20.1.1 to 20.3.1 in /python/helpers
- Bump golang.org/x/mod from 0.3.0 to 0.4.0 in /go_modules/helpers
- Bump @npmcli/arborist from 1.0.13 to 1.0.14 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.58 to 0.12.59 in /composer/helpers
- Bump friendsofphp/php-cs-fixer in /composer/helpers
- Bump eslint from 7.14.0 to 7.15.0 in /npm_and_yarn/helpers
- Bump eslint-plugin-prettier from 3.1.4 to 3.2.0 in /npm_and_yarn/helpers
- Bump semver from 7.3.2 to 7.3.4 in /npm_and_yarn/helpers
- Update rubocop requirement from ~> 1.4.2 to ~> 1.5.0 in /common

## v0.125.7, 30 November 2020

- Bump jest from 26.6.2 to 26.6.3 in /npm_and_yarn/helpers
- Bump prettier from 2.1.2 to 2.2.1 in /npm_and_yarn/helpers
- Bump @npmcli/arborist from 1.0.12 to 1.0.13 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.53 to 0.12.58 in /composer/helpers
- Bump pip-tools from 5.3.1 to 5.4.0 in /python/helpers
- Update rubocop requirement from ~> 0.93.0 to ~> 1.4.2 in /common
- Update simplecov requirement from ~> 0.19.0 to ~> 0.20.0 in /common
- Update gitlab requirement from = 4.16.1 to = 4.17.0 in /common
- Bundler: filter relevant credentials for all native helpers @baseballlover723
- CI: Fix dependabot-core-ci build by removing buildkit caching

## v0.125.6, 27 November 2020

- Pip compile: raise DependencyFileNotResolvable error when initial manifest
  files are unresolvable
- JS: Handle rate limited npm package requests
- Go mod: verify Dependabot::GitDependenciesNotReachable from versioned
- dry-run: add exception handling and re-raise on unknown errors

## v0.125.5, 25 November 2020

- go_modules: raise Dependabot::GitDependenciesNotReachable for dependencies missing from github.com
- JS: Prefer the npm conflicting dependency parser
- Clean go_modules build cache in dependabot/dependabot-core docker image
- Check Azure PR description against utf-16 encoded length
- Bump @npmcli/arborist from 1.0.10 to 1.0.12 in /npm_and_yarn/helpers
- Bump npm from 6.14.8 to 6.14.9 in /npm_and_yarn/helpers
- Bump eslint from 7.12.1 to 7.14.0 in /npm_and_yarn/helpers

## v0.125.4, 17 November 2020

- Yarn: Explain conflicting top-level dependency

## v0.125.3, 16 November 2020

- Bundler: Add top-level dependency to conflict explanation
- Use conflicting deps explanation in the dry-run script
- Bundler: Add explanation message to conflicting dependencies
- Add js helper README with debugging tips.
- JS: Include the top-level npm dependency for conflicting dependencies
- Hex: support reading files in elixir supporting files like in mixfiles (@baseballlover723)
- Update simplecov-console requirement from ~> 0.7.2 to ~> 0.8.0
- Bump @npmcli/arborist from 1.0.9 to 1.0.10 in /npm_and_yarn/helpers
- Hex: support elixir `Code.require_file` like `Code.eval_file` (@baseballlover723)

## v0.125.2, 11 November 2020

- Update CI jobs env variable assignment (@baseballlover723)
- Hex: Support elixir `Code.eval_file` without specifying a relative directory (@baseballlover723)
- JS: Explain update not possible for yarn and npm
- Extract DependencyFileBuilder to remove duplication

## v0.125.1, 5 November 2020

- Escape `SharedHelpers.run_shell_command` with shellwords

## v0.125.0, 5 November 2020

- Bundler: Explain why security update was not possible
- Raise descriptive error when update is not possible
- Go mod: Handle post-v0 module path updates

## v0.124.8, 4 November 2020

- Add missing python versions: 3.6.12 3.6.11 3.6.10, 3.5.10 and 3.5.8

## v0.124.7, 3 November 2020

- composer: assume a helper terminated by `SIGKILL` is OutOfMemory
- dry-run: handle comma separated list of deps
- Bump jest from 26.6.1 to 26.6.2 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.49 to 0.12.53 in /composer/helpers
- Bump npm-user-validate from 1.0.0 to 1.0.1 in /npm_and_yarn/helpers

## v0.124.6, 2 November 2020

- Go mod: handle major version mismatch
- Cargo: handle caret version requirements

## v0.124.5, 30 October 2020

- Go mod: Bump gomodules-extracted [from commit](https://github.com/golang/go/commit/5b509d993d3a3a212b4033815be8b7b439fac672)
- Go mod: Add/fix specs for missing meta tag and packages that 404

## v0.124.4, 30 October 2020

- Ignore go files that start with underscore or dot
- Go mod: handle missing package url meta tags
- Ignore go files tagged with `+build`
- Handle missing VCS when converting git_source path
- Fix relative dir on mac where tmp is in /private
- Handle missing directory in cloned repo
- Improve relative path code in vendor updater
- Correctly handle vendored updates in nested directory
- Raise generic DependabotError when all else fails
- Mark unknown revision errors as DependencyFileNotResolvable
- Include backtrace from native bundler helpers
- Mount native bundler helpers in dev shell
- Bump friendsofphp/php-cs-fixer in /composer/helpers

## v0.124.3, 27 October 2020

- Rename fixes_advisory? to fixed_by? and handle mixed case names
- dry-run: add security_updates_only
- Bump eslint from 7.12.0 to 7.12.1 in /npm_and_yarn/helpers

## v0.124.2, 26 October 2020

- Add fixes_advisory? and affects_version? to security advisory
- Bump jest from 26.6.0 to 26.6.1 in /npm_and_yarn/helpers
- Bump composer/composer from 1.10.15 to 1.10.16 in /composer/helpers
- Bump poetry from 1.1.2 to 1.1.4 in /python/helpers
- Bump eslint from 7.11.0 to 7.12.0 in /npm_and_yarn/helpers

## v0.124.1, 22 October 2020

- Add lowest_security_fix_version method to update checkers

## v0.124.0, 20 October 2020

- Go: Promote experimental `go mod tidy` support to stable
  (i.e., always tidy if repo_contents_path is given)
- Go: Promote experimental `go mod vendor` support to stable
  (i.e., always vendor if repo_contents_path is given and vendor/modules.txt is present)
- Bump jest from 26.5.3 to 26.6.0 in /npm_and_yarn/helpers
- Bump object-path from 0.11.4 to 0.11.5 in /npm_and_yarn/helpers
- Bump composer/composer from 1.10.10 to 1.10.15 in /composer/helpers

## v0.123.1, 19 October 2020

- Go mod: Handle `cannot find module` during go mod tidy
- Python: Add 3.9.0 and upgrade pyenv to v1.2.21 (@ulgens)
- Bundler: Ignore changed .gemspec from vendor/cache folder

## v0.123.0, 13 October 2020

- Bundler: Refactored Dependabot's use of Bundler commands to shell out instead
  of running in a forked process.
  - This aligns Bundler with other package managers and will enable us to
    support other Bundler versions in future.

## v0.122.1, 13 October 2020

- Bump phpstan/phpstan from 0.12.48 to 0.12.49 in /composer/helpers
- Gracefully handle gomod package import that has changed
- Treat .bundlecache files as binary
- Check if files are binary using the `file` util
- Bump jest from 26.5.2 to 26.5.3 in /npm_and_yarn/helpers
- Bump eslint from 7.10.0 to 7.11.0 in /npm_and_yarn/helpers
- Update tests and fixtures for new Cargo.lock format
- Explicitly install version of rust toolchain
- Rust toolchain has been upgraded to 1.47.0. This means PRs will now try to
  upgrade the lockfile to cargo's v2 format.
- Update rubocop requirement from ~> 0.92.0 to ~> 0.93.0 in /common
- Add a fingerprint to generated gitconfigs
- If there isn't a backup gitconfig, remove the generated one
- dry-run: updater-opts via option

## v0.122.0, 7 October 2020

- Add experimental support for `go mod vendor`
- Enable code coverage reporting of dependabot-core

## v0.121.1, 7 October 2020

- Configure git when creating a temp repo for gomod updates
- Bump jest from 26.5.0 to 26.5.2 in /npm_and_yarn/helpers
- Bump poetry from 1.1.1 to 1.1.2 in /python/helpers
- Refactor: reusable VendorDependencies object

## v0.121.0, 6 October 2020

- Add experimental support for `go mod tidy`

## v0.120.5, 6 October 2020

- Allow requirements.txt files of up to 200kb
- Bump poetry from 1.0.10 to 1.1.1 in /python/helpers
- Bump jest from 26.4.2 to 26.5.0 in /npm_and_yarn/helpers
- Reduce docker image size (@wreulicke)
- Bump phpstan/phpstan from 0.12.47 to 0.12.48 in /composer/helpers
- Update rubocop requirement from ~> 0.91.0 to ~> 0.92.0 in /common
- Adds python 3.7.9. (@jeremiq)

## v0.120.4, 1 October 2020

- Go: Bump golang to v1.15.2
- Bump phpstan/phpstan from 0.12.45 to 0.12.47 in /composer/helpers
- Upgrade Python to 3.8.6 (@ulgens)
- Handle empty pipfile requirement string
- Teach FileFetcher to fetch from disk if local repository clone is present
- Bundler: refactor DependencySource from LatestVersionFinder

## v0.120.3, 28 September 2020

- Fix uninitialized constant error (`Dependabot::VERSION`) when using `SharedHelpers`
- Fix `SharedHelpers.excon_defaults` when passing in extra headers
- Bump phpstan/phpstan from 0.12.44 to 0.12.45 in /composer/helpers
- Bump eslint from 7.9.0 to 7.10.0 in /npm_and_yarn/helpers

## v0.120.2, 25 September 2020

- Add trailing slash to pypi.org index requests
- Add a default User-Agent header to excon requests
- Bump phpstan/phpstan from 0.12.43 to 0.12.44 in /composer/helpers

## v0.120.1, 25 September 2020

- Default to pypi.org instead of pypi.python.org

## v0.120.0, 24 September 2020

- BREAKING: New exception `Dependabot::PullRequestCreator::AnnotationError`
  Raised when a pull request is created but fails further steps (e.g. assigning reviewer)
  Code that rescues from `PullRequestCreator` can use the `pull_request` property for the
  incomplete PR, and the `cause` property for the original error.
- Allow Azure client to set linked work item (@JamieMagee)
- Bump eslint from 7.8.1 to 7.9.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.42 to 0.12.43 in /composer/helpers
- Bump prettier from 2.1.1 to 2.1.2 in /npm_and_yarn/helpers
- Bump rubocop from ~> 0.90.0 to ~> 0.91.0 in /common
- Bump jason from 1.2.1 to 1.2.2 in /hex/helpers

## v0.119.6, 21 September 2020

- Fix a bug generating commit messages introduced in v0.119.5
- bundler: add temporary support for persistent_gems_after_clean

## v0.119.5, 21 September 2020

- Fix missing notice in PR content when source text is truncated
- composer: remove root cache
- nuget: Force encode nuspec files to utf-8 for regex matching

## v0.119.4, 15 September 2020

- hex: fix lockfile updating transitive dependencies
- python: fix python path dependencies with file (@lfdebrux)
- Upgrade elixir/mix to 1.10.4
- Bump rubocop from ~> 0.88.0 to ~> 0.90.0 in /common

## v0.119.3, 10 September 2020

- Fix for nuget v2 responses that don't specify a base (@ppejovic)
- formatting changes to avoid linting errors
- Upgrade elixir/mix to 1.10.0
- Add OAuth support to Azure client
- Bump eslint from 7.7.0 to 7.8.1 in /npm_and_yarn/helpers
- Bump prettier from 2.0.5 to 2.1.1 in /npm_and_yarn/helpers

## v0.119.2, 2 September 2020

- Support cargo 1.46.0 ref not found message
- Don't downgrade a pinned commit to a tag. (@reitermarkus)
- Dockerfile.dev: set git author

## v0.119.1, 28 August 2020

- Bump phpstan/phpstan from 0.12.37 to 0.12.39 in /composer/helpers
- Update to poetry to 1.0.10
- Add beta support for vendoring git dependencies in Bundler

## v0.119.0, 26 August 2020

- Only replace version part of cargo line
- Add beta support for vendoring dependencies in Bundler

## v0.118.16, 20 August 2020

- Add a optional repo_contents_path attribute to the file parser/fetcher/updater

## v0.118.15, 20 August 2020

- Handle deleting binary files in the PR creator/updater

## v0.118.14, 20 August 2020

- Support binary and deleted files in PR updater/creator

## v0.118.13, 19 August 2020

- Add deleted and content_encoding properties to dependency_file
- Bump npm from 6.14.4 to 6.14.8 in /npm_and_yarn/helpers
- Bump eslint from 7.6.0 to 7.7.0 in /npm_and_yarn/helpers
- Bump jest from 26.2.2 to 26.4.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.34 to 0.12.37 in /composer/helpers
- Add python 3.7.8
- Test caching strategy from old circle config

## v0.118.12, 7 August 2020

- docker: consistent indentation of Dockerfile (@localheinz)
- python: properly escape username nad password in auth URL
- CI: publish versioned images to DockerHub
- CI: performance improvements

## v0.118.11, 6 August 2020

- common: increase default http client read timeout
- go_modules: always return a Version object for indirect dependencies
- Bump composer/composer from 1.10.9 to 1.10.10 in /composer/helpers
- Bump pip-tools from 5.3.0 to 5.3.1 in /python/helpers
- CI: performance improvements

## v0.118.10, 3 August 2020

- Bump jest from 26.2.1 to 26.2.2 in /npm_and_yarn/helpers
- Bump eslint from 7.5.0 to 7.6.0 in /npm_and_yarn/helpers
- Encode '@' in python HTTP basic auth passwords

## v0.118.9, 3 August 2020

- CI: Move from Circle CI to actions
- CI: Use job matrix @localheinz
- Composer: Best practices for 7.4 @localheinz
- Composer: Explicitly require latest stable version of composer/composer @localheinz
- Actions: Fix updating actions that are quoted
- Bump jest from 26.1.0 to 26.2.1 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.33 to 0.12.34 in /composer/helpers
- Bump pip-tools from 5.2.1 to 5.3.0 in /python/helpers

## v0.118.8, 24 July 2020

- Upgrade Python version to 3.8.5 (@ulgens)
- Copy composer from the composer image
- Attempt to fix error where version is added to path dependency (@jtbeach)
- Undefined names: import PipSession and parse_requirements
- Update python/spec/dependabot/python/update_checker/pipenv_version_resolver_spec.rb
- Upgrade default python version to 3.8.4 (@ulgens)
- Update excon to 0.75.0
- Bump friendsofphp/php-cs-fixer in /composer/helpers
- Bump npm-registry-fetch from 4.0.3 to 4.0.5 in /npm_and_yarn/helpers
- Bump composer/composer from 1.10.8 to 1.10.9 in /composer/helpers
- Bump cython from 0.29.20 to 0.29.21 in /python/helpers
- Bump phpstan/phpstan from 0.12.31 to 0.12.33 in /composer/helpers
- Update gitlab requirement from = 4.15.0 to = 4.16.1 in /common
- Bump eslint from 7.4.0 to 7.5.0 in /npm_and_yarn/helpers
- Fix npm indentation spec
- Add rubygems stubbed info responses
- Bump rubocop to 0.88.0
- Fix docker-dev-shell ruby/php build
- Add native version range syntax support for NuGet (@eager)
- Bump eslint from 7.3.1 to 7.4.0 in /npm_and_yarn/helpers
- Use Maven version ranges for ignored_versions in Maven and Gradle (@eager)

## v0.118.7, 2 July 2020

- Python: support binary path dependencies when using requirements.txt/in files

## v0.118.6, 30 June 2020

- Bump phpstan/phpstan from 0.12.30 to 0.12.31 in /composer/helpers
- Bump composer/composer from 1.10.7 to 1.10.8 in /composer/helpers
- Prefer exact match for 'security' label @qnighy

## v0.118.5, 24 June 2020

- Actions: Fix multiple sources matching major versions
- Maven: Add support for dependency classifiers @a1flecke
- Add support for `+` separator when calculating semver change @a1flecke
- Bump eslint from 7.3.0 to 7.3.1 in /npm_and_yarn/helpers
- Bump prettier from 2.0.4 to 2.0.5 in /npm_and_yarn/helpers
- Bump jason from 1.2.0 to 1.2.1 in /hex/helpers
- Bump eslint from 7.2.0 to 7.3.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.29 to 0.12.30 in /composer/helpers

## v0.118.4, 19 June 2020

- Safely output markdown from link_and_mention_sanitizer
- Bump composer/composer from 1.10.6 to 1.10.7 in /composer/helpers

## v0.118.3, 18 June 2020

- Correctly handle path dependencies in composer
- Bump eslint from 6.8.0 to 7.2.0 in /npm_and_yarn/helpers
- Bump composer/composer from 1.9.3 to 1.10.6 in /composer/helpers
- Bump eslint-plugin-prettier from 3.1.3 to 3.1.4 in /npm_and_yarn/helpers
- Bump cython from 0.29.19 to 0.29.20 in /python/helpers
- Bump pip-tools from 5.1.2 to 5.2.1 in /python/helpers
- Bump phpstan/phpstan from 0.12.19 to 0.12.29 in /composer/helpers
- Bump poetry from 1.0.8 to 1.0.9 in /python/helpers
- Bump hashin from 0.14.6 to 0.15.0 in /python/helpers
- [Python] Add parsing of environment markers (@mayeut)

## v0.118.2, 16 June 2020

- GitHub Actions: Handle multiple sources for the same action
- Gradle: Add support for properties set as defaults, supports both the
  findProperty and hasProperty syntax styles.
- Nuget: Added support for <PackageVersion> elements with MSBuild projects
- GitLab: Add pull_request_updater
- Handle missing repo when fetching recent commits
- Handle new protected branch error when updating PRs
- Update rubocop requirement from ~> 0.83.0 to ~> 0.85.0 in /common
- Upgrade poetry to 1.0.8
- Update vcr requirement from = 5.0 to = 6.0.0 in /common
- Update gitlab requirement from = 4.14.1 to = 4.15.0 in /common
- Specs: Update rubygems index and stubbed info responses

## v0.118.1, 4 June 2020

- Handle cargo native dependencies
- Fix failing non-existing author email (@hsyn)
- docker-dev-shell --rebuild no args

## v0.118.0, 29 May 2020

- Remove support for jinja requimrents files
- Upgrade python helpers to latest version of pip
- Bump pip from 19.3.1 to 20.1.1
- Bump pip-tools from 4.5.1 to 5.1.2 in /python/helpers

## v0.117.11, 28 May 2020

- Optionally raise Dependabot::AllVersionsIgnored when all potential updates are ignored
- Update Python version to 3.8.3 and 2.8.18 (@ulgens)

## v0.117.10, 21 May 2020

- Always use exact dependencies label if one exists
- Bump cython from 0.29.18 to 0.29.19 in /python/helpers
- go_modules: Handle multiline errors
- docker-dev-shell: rebuild core image when passing `--rebuild` option

## v0.117.9, 19 May 2020

- Handle protected branches enforcing linear history
- Bump cython from 0.29.17 to 0.29.18 in /python/helpers
- Update rubocop requirement from ~> 0.82.0 to ~> 0.83.0 in /common

## v0.117.8, 12 May 2020

- gradle: Fix version types in gradle to allow matching postfixed version types
- bundler: Sanitize Dir.chdir calls in gemspecs
- go_modules: Remove unnecessary `require`s from go.mod
- dependencies: Fix acorn vulnerability

## v0.117.7, 20 April 2020

- Nuget: Handle version requirements with suffix
- Bump eslint-plugin-prettier from 3.1.2 to 3.1.3 in /npm_and_yarn/helpers
- Bump jest from 25.3.0 to 25.4.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.18 to 0.12.19 in /composer/helpers
- Update rubocop requirement from ~> 0.80.1 to ~> 0.82.0 in /common
- Bump friendsofphp/php-cs-fixer in /composer/helpers
- Bump semver from 7.1.3 to 7.3.2 in /npm_and_yarn/helpers

## v0.117.6, 9 April 2020

- Handle unauthorized pushes to protected branches
- Bump jest from 25.2.3 to 25.3.0 in /npm_and_yarn/helpers
- Bump prettier from 2.0.2 to 2.0.4 in /npm_and_yarn/helpers

## v0.117.5, 31 March 2020

- Adds python 3.7.7 (@sobolevn)
- Bump jest from 25.2.0 to 25.2.3 in /npm_and_yarn/helpers
- Bump jest from 25.1.0 to 25.2.0 in /npm_and_yarn/helpers
- Bump npm from 6.14.3 to 6.14.4 in /npm_and_yarn/helpers
- Bump cython from 0.29.15 to 0.29.16 in /python/helpers

## v0.117.4, 24 March 2020

- Bump prettier from 1.19.1 to 2.0.2 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.14 to 0.12.18 in /composer/helpers
- Bump npm from 6.14.2 to 6.14.3 in /npm_and_yarn/helpers
- Upgrade to PHP 7.4 (@kubawerlos)
- python: upgrade to poetry ^1.0.0 (@tommilligan)
- Update pyenv version (@ulgens)
- Update Python version to 3.8.2 (@ulgens)
- Bump acorn from 6.3.0 to 6.4.1 in /npm_and_yarn/helpers
- Update gitlab requirement from = 4.13.1 to = 4.14.1 in /common

## v0.117.3, 20 March 2020

- Update Maven Requirement (@a1flecke)

## v0.117.2, 9 March 2020

- Improve PR descriptions for non-github PR's
- Correctly mark requirements as not up to date

## v0.117.1, 5 March 2020

- Bump npm from 6.14.1 to 6.14.2 in /npm_and_yarn/helpers
- Gradle: Add support for authenticated repositories (@GeorgiosGoniotakis)
- Bump phpstan/phpstan from 0.12.12 to 0.12.14 in /composer/helpers

## v0.117.0, 3 March 2020

- Maven: Add support for "+" Semver Build Identifier
- Sanitize github ref links in plaintext/rdoc
- Codecommit: Ensures a commit is created before opening a PR
- Hex: Fix mix.lock file parser for hex 0.20.2+
- Bump rubocop requirement from ~> 0.79.0 to ~> 0.80.1 in /common
- Bump phpstan/phpstan from 0.12.08 to 0.12.12 in /composer/helpers
- Bump npm from 6.13.7 to 6.14.1 in /npm_and_yarn/helpers
- Bump pip-tools from 4.4.1 to 4.5.1 in /python/helpers
- Bump semver from 7.1.2 to 7.1.3 in /npm_and_yarn/helpers
- Bump cython from 0.29.14 to 0.29.15 in /python/helpers
- Bump rimraf from 3.0.1 to 3.0.2 in /npm_and_yarn/helpers
- Bump composer/composer from 1.9.2 to 1.9.3 in /composer/helpers
- Remove security_updates_only (unused)

## v0.116.6, 3 February 2020

- Better branch name sanitisation

## v0.116.5, 31 January 2020

- Bump semver from 7.1.1 to 7.1.2 in /npm_and_yarn/helpers
- Add security updates only option to the update checker (unused)

## v0.116.4, 29 January 2020

- Bump npm from 6.13.6 to 6.13.7 in /npm_and_yarn/helpers
- Bump rimraf from 3.0.0 to 3.0.1 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.12.5 to 0.12.8 in /composer/helpers
- Maven: Add Support for Semver Build Identifier "+"
- Bump commonmarker requirement from ~> 0.20.1 to >= 0.20.1, < 0.22.0
- Bump jest from 24.9.0 to 25.1.0 in /npm_and_yarn/helpers
- Bump pip-tools from 4.3.0 to 4.4.0 in /python/helpers

## v0.116.3, 20 January 2020

- Git Dependencies: Respect HTTP scheme for service pack URLs
- Maven: Support properties with attributes
- Bump composer/composer from 1.9.1 to 1.9.2 in /composer/helpers
- Bump phpstan/phpstan from 0.12.4 to 0.12.5 in /composer/helpers

## v0.116.2, 10 January 2020

- Go Modules: Stop trying to update indirect deps
- Bump npm from 6.13.4 to 6.13.6 in /npm_and_yarn/helpers

## v0.116.1, 8 January 2020

- Hex: fix file fetching for nested umbrella apps

## v0.116.0, 8 January 2020

- Python: Fix latest version finder when the dependency name has extras
- Go Modules: Fix version comparison in `SecurityAdvisory`
- Bump default Python to 3.8.1 and add 3.7.6 to allowed versions
- [Security] Bump handlebars from 4.1.2 to 4.5.3 in /npm_and_yarn/helpers
- Bump rubocop requirement from ~> 0.78.0 to ~> 0.79.0 in /common
- Bump phpstan/phpstan from 0.12.3 to 0.12.4 in /composer/helpers
- Bump eslint from 6.7.2 to 6.8.0 in /npm_and_yarn/helpers

## v0.115.3, 20 December 2019

- Handle links with breaks in the link sanitizer

## v0.115.2, 20 December 2019

- Update gitlab requirement from = 4.12 to = 4.13.1 in /common
- Refactor sanitize_mentions method to use commonmarker

## v0.115.1, 19 December 2019

- Python: Fix dep name extras bug in metadafinder
- Update rubocop requirement from ~> 0.77.0 to ~> 0.78.0 in /common

## v0.115.0, 18 December 2019

- Bump semver from 7.1.0 to 7.1.1 in /npm_and_yarn/helpers
- Refactor sanitize_links method
  - HTML is now output in Dependabot::PullRequestCreator::MessageBuilder#pr_message.

## v0.114.1, 17 December 2019

- Bump semver from 7.0.0 to 7.1.0 in /npm_and_yarn/helpers

## v0.114.0, 16 December 2019

- GitLab: Pass all assignees to merge request creator
- Bump phpstan/phpstan from 0.11.19 to 0.12.3 in /composer/helpers
- Bump eslint-plugin-prettier from 3.1.1 to 3.1.2 in /npm_and_yarn/helpers
- Bump semver from 6.3.0 to 7.0.0 in /npm_and_yarn/helpers

## v0.113.28, 12 December 2019

- Bump npm from 6.13.2 to 6.13.4 in /npm_and_yarn/helpers
- Bump @dependabot/yarn-lib from 1.21.0 to 1.21.1 in /npm_and_yarn/helpers
- Python: Preserve dependency name extras

## v0.113.27, 9 December 2019

- JS: Fix unfetchable tarball path deps ∞ loop
- Codecommit: Create client without credentials
- Bump npm from 6.13.1 to 6.13.2 in /npm_and_yarn/helpers
- Bump @dependabot/yarn-lib from 1.19.2 to 1.21.0 in /npm_and_yarn/helpers
- Bump eslint from 6.7.1 to 6.7.2 in /npm_and_yarn/helpers

## v0.113.26, 29 November 2019

- Cargo: Handle virtual manifests with workspace glob on src/*

## v0.113.25, 28 November 2019

- Bump default Python from 3.7.5 to 3.8.0
- Update rubocop requirement from ~> 0.76.0 to ~> 0.77.0 in /common
- Docker: support mixed case version suffixes (RC)
- Support Jina templates in requirements files

## v0.113.24, 26 November 2019

- Bump friendsofphp/php-cs-fixer in /composer/helpers
- Bump pip-tools from 4.2.0 to 4.3.0 in /python/helpers

## v0.113.23, 25 November 2019

- JS: Fetch tarball path dependencies
- Bump eslint from 6.6.0 to 6.7.1 in /npm_and_yarn/helpers

## v0.113.22, 22 November 2019

- Bump @dependabot/yarn-lib from 1.19.1 to 1.19.2 in /npm_and_yarn/helpers
- Add pull request message header support (thanks, @millerick!)
- Go: Add go version specifier (thanks, @chenrui333!)
- Go: Bump golang to v1.13.4 (thanks, @chenrui333!)
- Docker: Support mix of Docker tags for the same image (thanks, @michael-booth!)
- Maven: Change logic to check if a version is released

## v0.113.21, 19 November 2019

- Bump npm from 6.13.0 to 6.13.1 in /npm_and_yarn/helpers
- Bump https-proxy-agent in /npm_and_yarn/helpers
- Bump prettier from 1.18.2 to 1.19.1 in /npm_and_yarn/helpers
- Fix Gitlab API commit file type to match GitHub's submodule type

## v0.113.20, 6 November 2019

- Decompress gzipped http responses
- Bump npm from 6.12.1 to 6.13.0 in /npm_and_yarn/helpers
- Bump pip from 19.2.3 to 19.3.1 in /python/helpers
- Gradle: Skip name property if we already present

## v0.113.19, 5 November 2019

- Common: Fix hanging regex in LinkAndMentionSanitizer
- Bump cython from 0.29.13 to 0.29.14 in /python/helpers
- Bump composer/composer from 1.9.0 to 1.9.1 in /composer/helpers
- Bump default Python versions to 3.7.5 and 2.7.17
- Bump nock from 11.6.0 to 11.7.0 in /npm_and_yarn/helpers
- GitLab: Don't pass empty array to update approvers

## v0.113.18, 30 October 2019

- Bump pip-tools from 4.1.0 to 4.2.0 in /python/helpers

## v0.113.17, 30 October 2019

- Bump npm from 6.10.3 to 6.12.1 in /npm_and_yarn/helpers
- Update rubocop requirement from ~> 0.75.0 to ~> 0.76.0 in /common
- Update toml-rb requirement from ~> 1.1, >= 1.1.2 to >= 1.1.2, < 3.0

## v0.113.16, 28 October 2019

- Fix mismatched code span issue when sanitizing mentions
- Bump eslint from 6.5.1 to 6.6.0 in /npm_and_yarn/helpers
- Bump nock from 11.5.0 to 11.6.0 in /npm_and_yarn/helpers
- Bump phpstan/phpstan from 0.11.16 to 0.11.19 in /composer/helpers
- Add support for VS Code Remote Development on Docker
- Bump nock from 11.4.0 to 11.5.0 in /npm_and_yarn/helpers

## v0.113.15, 18 October 2019

- Add whatsnew to changelog names

## v0.113.14, 17 October 2019

- JS: Fix missing previous version when the version is a git sha

## v0.113.13, 16 October 2019

- JS: Fix bug where previous version was equal to the new version

## v0.113.12, 9 October 2019

- Gradle: Support updates that use git dependencies
- Improve @mention sanitizer for verbatim backticks in code fences

## v0.113.11, 8 October 2019

- Disable the Go module proxy

## v0.113.10, 7 October 2019

- Upgrade Go to 1.13.1

## v0.113.9, 3 October 2019

- Improve @mention sanitizer for compact code blocks
- JS: Handle GitHub shorthand links in MetadataFinder

## v0.113.8, 2 October 2019

- Python: Revert file fetching change

## v0.113.7, 1 October 2019

- Bump eslint from 6.5.0 to 6.5.1 in /npm_and_yarn/helpers
- Bump rubocop requirement from ~> 0.74.0 to ~> 0.75.0 in /common
- Bump @dependabot/yarn-lib from 1.17.3 to 1.19.0 in /npm_and_yarn/helpers

## v0.113.6, 30 September 2019

- Bundler: Fall back to unlocking all sub-dependencies in lockfile updater
- Python: Fetch path dependency files relative to directory they're required in
- Python: Handle nested path dependencies during parsing

## v0.113.5, 30 September 2019

- JS: Handle cases where the resolved previous version is the latest version

## v0.113.4, 27 September 2019

- JS: Resolve the previous version from the version requirements when there is
  no lockfile
- JS: Handle malformed lockfile versions

## v0.113.3, 26 September 2019

- Gradle: Support pre-release syntax 1.0.0pr
- Update security vulnerability disclosure to GitHub Bug Bounty program

## v0.113.2, 25 September 2019

- Dependencies: Make gpgme an optional dependency
- Dev env: Allow a few options to be provided to the dev shell
- Dev env: Mount .rubocop.yml in the docker dev shell
- Dry-run: Only git init when writing output
- Dry run: support multiple package managers when caching files
- Dry run: add --commit option to fetch from

## v0.113.1, 17 September 2019

- Bump nock from 10.0.6 to 11.3.4 in /npm_and_yarn/helpers
- Bump eslint from 6.3.0 to 6.4.0 in /npm_and_yarn/helpers
- Dry run script: add options and improve logging

## v0.113.0, 13 September 2019

- Add support for AWS codecommit

## v0.112.37, 11 September 2019

- Python: Stricter marker ignoring
- Docker: Add support for docker images with build num as tags (thanks @tscolari!)

## v0.112.36, 10 September 2019

- Composer: Tighten platform extensions regex
- JS: Parse dependency on pkg.github.com registry more sensibly
- Python: import setuptools for access to both find_packages() and setup() (thanks @cclauss!)

## v0.112.35, 10 September 2019

- Add details of error to the "Unexpected git error!" message
- JS: Ignore user-specified registries that don't return JSON
- Handle bintray private registries

## v0.112.34, 9 September 2019

- Don't comment on cases where a GitHub bug prevents us adding a team reviewer

## v0.112.33, 7 September 2019

- .NET: Add support for GlobalPackageReference, Packages.props and using Update
  in addition to Include (thanks @david-driscoll)
- Reverse commit order when looking for most recent Dependabot commit
- Python: Bump hashin from 0.14.5 to 0.14.6 in /python/helpers
- Prioritise `changes` files over `history` files when looking for a changelog
- Sanitize gemfury URLs globally
- Composer: Helper cleanup (thanks @localheinz)

## v0.112.32, 3 September 2019

- PHP: Fix SHA pinning for git dependencies with an alias
- Ruby: Update Ruby versions
- Gradle: Exclude dependencies that don't have a valid version

## v0.112.31, 2 September 2019

- Rust: Remove default-run specification before running version resolution

## v0.112.30, 2 September 2019

- Python: Pass index URLs to pip-compile as arguments

## v0.112.29, 2 September 2019

- .NET: Include default source unless a config file clears it

## v0.112.28, 2 September 2019

- Comment on created PRs that we are unable to assign reviewers to

## v0.112.27, 2 September 2019

- Cargo: Better check for globs in workspace paths

## v0.112.26, 31 August 2019

- Sanitize issue/PR references that specify a repo

## v0.112.25, 30 August 2019

- Python: Update marker handling to ignore deps with a < in the requirement
- Composer: Fix tests and enforce latest_allowable_version for stability-flag versions

## v0.112.24, 30 August 2019

- Docker: Use most specific version for .0 releases

## v0.112.23, 30 August 2019

- Handle trailing dots when creating branch names

## v0.112.22, 29 August 2019

- JS: Use all dependency URLs when building a .npmrc (don't prefer one lockfile format)

## v0.112.21, 29 August 2019

- Composer: Tighter regex on installation requirements
- JS: Handle leading equals signs

## v0.112.20, 28 August 2019

- Bundler: Mimic Bundler 2.x default of using HTTPS for GitHub dependencies

## v0.112.19, 28 August 2019

- Composer: Refactor FileParser
- Composer: Support stability flags in parser and update checker
- Composer: Raise phpstan level from 5 to 6

## v0.112.18, 27 August 2019

- Composer: Smarter selection of implicit PHP requirements for applications

## v0.112.17, 27 August 2019

- Composer: Remove alias when determining git dependency branch

## v0.112.16, 27 August 2019

- Composer: Tighter regex for missing platform requirements

## v0.112.15, 27 August 2019

- Bundler: Don't update  gemspec requirements
- Bundler: Raise a runtime error if no files change in file updater

## v0.112.14, 26 August 2019

- Composer: Try to use lowest possible PHP version when updating requirements
- Python: Bump pip-tools from 4.0.0 to 4.1.0 in /python/helpers
- Bundler: Handle gemspec with a float version number

## v0.112.13, 26 August 2019

- Composer: More lockfile parsing robustness
- PHP: Handle doctored lockfile in FileParser
- Bundler: Update source for gemspec requirements when updating for Gemfile ones
- Switch back to npm v6.10.3

## v0.112.12, 26 August 2019

- Update Golang and Dep versions
- Composer: Parse git dependencies (ignore them in the update checker)
- Python: Bump pip from 19.2.2 to 19.2.3 in /python/helpers
- JS: Bump npm from 6.11.1 to 6.11.2 in /npm_and_yarn/helpers
- GitHub Actions: More precise file updating

## v0.112.11, 22 August 2019

- Yarn: Ignore dependencies with npm registry alias in the name (`alias@npm:package`)

## v0.112.10, 22 August 2019

- Handle git dependencies that pin to a tag in ReleaseFinder
- GitHub Actions: Update commit SHA pins to version pins when possible
- Add GitCommitChecker#pinned_ref_looks_like_commit_sha? method

## v0.112.9, 21 August 2019

- Bump npm from 6.10.3 to 6.11.1 in /npm_and_yarn/helpers

## v0.112.8, 21 August 2019

- Composer: Treat stability flag requirements as default requirement

## v0.112.7, 21 August 2019

- Composer: Don't update the commit SHA for git dependencies when doing other updates
- Update JS subdependencies

## v0.112.6, 20 August 2019

- Bump Rust version in Dockerfile
- Composer: Several internal improvements courtesy of @localheinz
- Python: Better GIT_DEPENDENCY_UNREACHABLE_REGEX for Poetry

## v0.112.5, 15 August 2019

- GitHub: Only update version tag if commit SHA has changed
- Look up a commit in GitCommitChecker#head_commit_for_current_branch if no version
- Better VERSION_REGEX for git commit checker
- Python: Handle arrays of Python requirements (from pyproject.toml) in PipenvVersionResolver

## v0.112.4, 15 August 2019

- JS: Add failing test for dependencies with latest

## v0.112.3, 15 August 2019

- JS: Better sanitization of {{ variable }} text in package.json files
- Composer: Handle php-64bit requirements
- PHP: Handle loosely specified PHP versions for libraries better

## v0.112.2, 14 August 2019

- PHP: Raise a Dependabot::DependencyFileNotResolvable error in some VersionResolver cases
- Better commit messages when updating a git tag without a lockfile

## v0.112.1, 14 August 2019

- Add github_actions as a gem everywhere

## v0.112.0, 14 August 2019

- Update dry run to cache editable dependency files
- Add support for updating GitHub Action workflow files

## v0.111.59, 12 August 2019

- Composer: Parse ranges with a wildcard as invalid

## v0.111.58, 12 August 2019

- .NET: Add Directory.Build.props regex to FileUpdater.updated_files_regex
- Add `require_up_to_date_base` filter to PullRequestCreator
- Expose GitMetadataFinder#head_commit_for_ref method

## v0.111.57, 12 August 2019

- Python: Update Python versions
- Python: Bump pip from 19.2.1 to 19.2.2 in /python/helpers

## v0.111.56, 9 August 2019

- Bundler: Handle path dependencies that use a .specification file
- Maven: Improve dot separator regex to fix XML searching bug

## v0.111.55, 8 August 2019

- PHP: Stricter regex for finding missing extensions and PHP versions
- Bundler: Tighter check on source being Rubygems

## v0.111.54, 8 August 2019

- Terraform: Handle registry dependencies that specify a sub-directory

## v0.111.53, 7 August 2019

- Retry tree creation if we're persistently failing to create a commit for it

## v0.111.52, 7 August 2019

- Better check that pull request creation errors have details
- Python: Better error message in pip-compile for bad Python version

## v0.111.51, 7 August 2019

- Gradle: Handle redirect loops
- Maven: Handle redirect loops
- Composer: Add special case for bad nova.laravel.com credentials

## v0.111.50, 6 August 2019

- Retry PR creation for unexpected 422s
- JS: Bump npm from 6.10.2 to 6.10.3 in /npm_and_yarn/helpers
- Update Excon requirement

## v0.111.49, 6 August 2019

- Bundler: Sanitize out date from gemspecs
- Python: Handle UnsupportedPythonVersion errors in pip-compile

## v0.111.48, 6 August 2019

- .NET: Treat blank versions the same as missing versions

## v0.111.47, 5 August 2019

- Rust: Ignore error in workspaces with clashing native dependencies
- Ignore merged PRs in PullRequestCreator::GitHub

## v0.111.46, 4 August 2019

- Python: Distinguish between dev and prod sub-dependencies (Poetry)
- Python: Distinguish between dev and prod sub-dependencies (Pipenv)
- PHP: Distinguish between production and development subdependencies
- Bundler: Simplify parser logic for subdependency_metadata

## v0.111.45, 4 August 2019

- JS: Include details of whether a sub-dependency is production or not
- Bundler: Detect whether subdependencies are production or not
- Validate subdependency_metadata format
- Store subdependency_metadata as an array of hashes (not a hash)

## v0.111.44, 3 August 2019

- Raise Octokit::Unauthorized from PullRequestCreator::GitHub if service pack 401s

## v0.111.43, 2 August 2019

- .NET:  Move blank version handling
- PHP: Bump composer/composer from 1.8.6 to 1.9.0

## v0.111.42, 2 August 2019

- .NET: Handle blank strings when comparing versions

## v0.111.41, 2 August 2019

- Handle Python homepage URLs that create a redirect loop
- Handle "could not add requested reviewers" errors

## v0.111.40, 31 July 2019

- Go (modules): switch to gomodules-extracted@v1.1.0
- Remove invalid .editorconfig file

## v0.111.39, 30 July 2019

- JS: Fix git URL parsing edge case
- Add missing pip support to dry-run

## v0.111.38, 29 July 2019

- JS: Ignore git dependencies locked to a non-commit version

## v0.111.37, 28 July 2019

- Elixir: Bump elixir version to 1.9.1 in Dockerfile

## v0.111.36, 27 July 2019

- .NET: Better pre-release comparison
- .NET: Fetch all nuget.config files

## v0.111.35, 26 July 2019

- JS: Better git URL parsing

## v0.111.34, 26 July 2019

- Python: Handle link tags without a href
- Bump cython from 0.29.12 to 0.29.13 in /python/helpers

## v0.111.33, 26 July 2019

- Don't map all git dependencies to GitHub
- Handle credentials with an `@` in the username in GitMetadataFetcher

## v0.111.32, 26 July 2019

- Don't use semver labels if a skip-release label exists

## v0.111.31, 26 July 2019

- Python: Handle devpi index requirements (package name in URL, must request
  text/html)

## v0.111.30, 26 July 2019

- Python: Use namespace when using NameNormaliser

## v0.111.29, 26 July 2019

- Python: Regex updates for new pip version

## v0.111.28, 25 July 2019

- Python: Update error message parsing for new pip version
- Python: Bump pip-tools from 3.9.0 to 4.0.0 in /python/helpers
- Python: Bump pip from 19.1.1 to 19.2.1 in /python/helpers
- Python: Handle pip-compiled files with specified names (when included in
  header)
- Composer: Better selection of valid versions from requirements

## v0.111.27, 24 July 2019

- JS: Bump semver from 6.2.0 to 6.3.0 in /npm_and_yarn/helpers
- JS: Bump npm from 6.10.1 to 6.10.2 in /npm_and_yarn/helpers

## v0.111.26, 23 July 2019

- Python: Fix typo

## v0.111.25, 23 July 2019

- Add new Dependency.name_normaliser_for_package_manager method, and implement
  for Python
- Python: Consider whether a version has been yanked in LatestVersionFinder
- Bundler: Stop using --full-index, since artifactory issue is now fixed

## v0.111.24, 22 July 2019

- Python: Correctly check for hashes when freezing versions in a pyproject.toml
- Don't pluralize security fixes if there is only one

## v0.111.23, 22 July 2019

- Yarn: Use npmjs.org as registry if explicitly specified in .yarnrc

## v0.111.22, 21 July 2019

- Composer: Fix conversion of requirements to version when handling missing
  extensions

## v0.111.21, 20 July 2019

- Python: Handle git@ URLs in FileFetcher

## v0.111.20, 19 July 2019

- Python: Check using Python 2 when updating fails due to an issue with dep
  being updated

## v0.111.19, 19 July 2019

- PHP: Use lower bound of library PHP requirement when resolving

## v0.111.18, 19 July 2019

- Properly catch pandoc timeouts

## v0.111.17, 19 July 2019

- Catch pandoc timeouts

## v0.111.16, 19 July 2019

- Time out calls to pandoc after 10 seconds
- Python: Bump pip-tools from 3.8.0 to 3.9.0 in /python/helpers

## v0.111.15, 17 July 2019

- Handle 401s from GitHub in GitMetadataFetcher
- Bundler: Handle symbols being used for requirements

## v0.111.14, 17 July 2019

- Python: Handle authed URLs which include an `@` in metadata finder
- Maven: Handle bad URIs in VersionFinder

## v0.111.13, 16 July 2019

- .NET: Ignore .sln files that can't be encoded to UTF-8
- Handle disabled repos in PullRequestCreator::Github

## v0.111.12, 16 July 2019

- Bundler: Replace JSON.parse lines in gemspec

## v0.111.11, 16 July 2019

- Yarn: Add support for missing `link:` path dependencies which exist in the
  lockfile
- Update rubocop requirement from ~> 0.72.0 to ~> 0.73.0 in /common

## v0.111.10, 15 July 2019

- JS: Fix yarn file path resolutions when manifest is missing

## v0.111.9, 15 July 2019

- Better library definition in PullRequestCreator

## v0.111.8, 15 July 2019

- Gradle: Handle dependency names that can't be converted to XPaths
- Maven: Fetch modules listed in profiles
- Handle @-mentions that include a hyphen

## v0.111.7, 14 July 2019

- Docker: Insist on updated docker_registry2 to fix Artifactory bug
- Yarn: Enforce https for most common hostnames
- Yarn: Bump @dependabot/yarn-lib from 1.16.0 to 1.17.3 in /npm_and_yarn/helpers

## v0.111.6, 13 July 2019

- Go (modules): bump masterminds/vcs to v1.13.1 to fix Go bitbucket support

## v0.111.5, 13 July 2019

- Cascade author details to Azure commit
- JS: Bump npm from 6.10.0 to 6.10.1 in /npm_and_yarn/helpers

## v0.111.4, 11 July 2019

- JS: Fetch yarn file path resolutions from manifest
- JS: Bump lodash from 4.17.11 to 4.17.14 in /npm_and_yarn/helpers

## v0.111.3, 8 July 2019

- Fix typo

## v0.111.2, 8 July 2019

- Mark fetched symlinks as symlinks, and update the target when updating
- Maven/Gradle: Make version classes consistent
- Look for previous version in changelogs as well as new version
- Composer: Handle PHP requirements with an OR condition

## v0.111.1, 7 July 2019

- Sanitize `gh-` links (i.e., handle lowercase)
- Python: Bump cython from 0.29.11 to 0.29.12 in /python/helpers
- Docker: Handle versions with a KB prefix (imperfectly...)
- Docker: Allow uppercase prefixes and suffixes
- Update Pyenv, Elixir and Rust versions

## v0.111.0, 5 July 2019

- PHP: Composer missing extension support
- Python: Fix typo
- Python: Bump poetry from 0.12.16 to 0.12.17 in /python/helpers

## v0.110.17, 4 July 2019

- Python: Handle unparseable python_requires values in setup.py
- Handle commit messages that are just a newline
- Python: Better Python requirement parsing

## v0.110.16, 4 July 2019

- JS: Bump npm from 6.9.2 to 6.10.0 in /npm_and_yarn/helpers

## v0.110.15, 3 July 2019

- Python: Add PipVersionResolver
- Python: Parse setup.py python_requires lines
- Fix rubocop

## v0.110.14, 2 July 2019

- .NET: Raise clearer file fetching error when a path in a .sln file can't be fetched
- JS: Store status on registry errors
- Python: Move Python version requirement detection into its own class

## v0.110.13, 2 July 2019

- Don't treat dependencies where we can't update the requirement file as updatable
- JS: Bump npm from 6.9.0 to 6.9.2 in /npm_and_yarn/helpers
- JS: Bump semver from 6.1.2 to 6.2.0 in /npm_and_yarn/helpers

## v0.110.12, 1 July 2019

- Composer: Parse auth.json to fetch credentials

## v0.110.11, 1 July 2019

- Python: Treat != requirements as unfixable

## v0.110.10, 1 July 2019

- Rust: Include user-agent when making requests to crates.io

## v0.110.9, 1 July 2019

- Ruby: Raise helpful error for plugin sources
- Ruby: Skip requirements which include an or

## v0.110.8, 30 June 2019

- Strip @ from branch name

## v0.110.7, 30 June 2019

- Python: More robust exclusion of path and git dependencies

## v0.110.6, 30 June 2019

- Terraform: Quietly ignore custom registries (don't raise)
- Python: Handle wildcards with trailing characters in requirement parser
- Python: Bump cython from 0.29.10 to 0.29.11 in /python/helpers
- Docker: Handle case where new digest can't be found

## v0.110.5, 29 June 2019

- NuGet: Fetch build files case insensitively
- NuGet: Fetch Directory.Build.targets files

## v0.110.4, 29 June 2019

- NuGet: Handle non-utf-8 encodings from registry

## v0.110.3, 29 June 2019

- NuGet: Handle zero padding around registry responses

## v0.110.2, 28 June 2019

- Python: Use Nokogiri to parse simple index response

## v0.110.1, 28 June 2019

- Docker: Paginate through all tags when registry returns paginated response
- Handle custom commit message prefixes for dev dependencies

## v0.110.0, 27 June 2019

- Implemented Azure client for file fetcher/pull request creator
  (see #1211. Thanks @chris5287!)

## v0.109.1, 26 June 2019

- Ruby: Handle precision mismatch when updating ranges

## v0.109.0, 26 June 2019

- BREAKING: Allow commit_message_options to be passed to pull request creator.
  This replaces the signoff_details argument. See #1227 for full details.

## v0.108.25, 25 June 2019

- Ruby: Handle unreleased git dependencies properly
- Add tests for PrNamePrefixer

## v0.108.24, 25 June 2019

- Python: Handle multiline links in PyPI simple index response

## v0.108.23, 25 June 2019

- JS: Handle Excon::Error::Socket errors when fetching latest details
- Raise helpful error for unexpected Bitbucket responses

## v0.108.22, 24 June 2019

- Composer: Handle stability flags in version updater
- JS: Bump semver from 6.1.1 to 6.1.2 in /npm_and_yarn/helpers
- PHP: Add php7.3-geoip to Dockerfile

## v0.108.21, 23 June 2019

- Add longer read timeout when fetching git metadata
- PHP: Handle leading space in requirement strings
- Python: Use --pre in pip-compile options if it was used previously
- Go (modules): keep bumping pinned dependencies
- Go (modules): don't update replace-pinned dependencies
- Sanitize markdown in commit messages
- Python: Handle a specified python version in LatestVersionFinder

## v0.108.20, 18 June 2019

- Python: Better backup parsing of setup.py files

## v0.108.19, 18 June 2019

- .NET: Handle multi-line sln declarations, and tighten regex. Fixes #520

## v0.108.18, 14 June 2019

- Python: Handle quotes around index URLs in requirement.txt files

## v0.108.17, 14 June 2019

- Npm: Ignore bundled sub-dependencies

## v0.108.16, 14 June 2019

- JS: Handle unexpected objects in package-lock.json when looking for path dependencies

## v0.108.15, 13 June 2019

- PHP: Add ext-imap to Dockerfile

## v0.108.14, 12 June 2019

- Python: Handle requirement files with spaces before their comments

## v0.108.13, 12 June 2019

- Gradle: Treat Early Access Programme (EAP) versions as pre-releases
- Cargo: Handle implicit workspace declarations
- Docker: Retry server errors
- Composer: Bump composer/composer from 1.8.5 to 1.8.6

## v0.108.12, 11 June 2019

- Go (modules): handle replace directive in updater

## v0.108.11, 11 June 2019

- Python: Properly remove setup tools warning

## v0.108.10, 10 June 2019

- Go (modules): don't build during go get -d

## v0.108.9, 10 June 2019

- Bundler: Remove existing load paths before loading git dependency gemspecs
- NuGet: Additional handling for timeouts from private registries

## v0.108.8, 8 June 2019

- Maven, Gradle: Special case display name for undescriptive artifact IDs
- Make dependency display name configurable by package manager
- JS: Ignore invalid lerna.json setups

## v0.108.7, 7 June 2019

- Docker: Support tag format with 'v' prefix
- Python: Bump pip-tools from 3.7.0 to 3.8.0 in /python/helpers

## v0.108.6, 6 June 2019

- Go (modules): handle local module replacements

## v0.108.5, 6 June 2019

- JS: Sanitize escaped slashes in package names for issue details

## v0.108.4, 6 June 2019

- Sanitize each cascade separately, to ensure truncated codeblocks don't cause issues
- Rust: Handle blank versions specified within a hash
- Fix method name typo
- Python: Raise an error for self-referential requirements files
- Docker: Retry RestClient::ServerBrokeConnection

## v0.108.3, 6 June 2019

- Better error for debugging repeated branch creation failure
- Bump js-yaml from 3.13.0 to 3.13.1 in /npm_and_yarn/helpers
- Composer: Retry more transitory failure classes in LockfileUpdater

## v0.108.2, 5 June 2019

- Python: Handle flags in requirement file, and fetch constraints files better
- Scope reference creation failure retries to a tighter error, and retry more
- JS: Bump handlebars from 4.1.0 to 4.1.2 in /npm_and_yarn/helpers
- Handle git URL that separate with :/
- Ruby: Call uniq on unreachable git URIs

## v0.108.1, 5 June 2019

- Python: Handle files that can't be encoded to UTF-8
- Improve file encoding in changelog fetching

## v0.108.0, 5 June 2019

- Pass signoff_details to MessageBuilder, not author_details
- Put emoji tighter together when prefixing with multiple

## v0.107.48, 4 June 2019

- Better mention sanitizing (handle codeblocks)

## v0.107.47, 4 June 2019

- JS: Handle creds used by multiple scopes in npmrc builder
- .NET: Handle v2 responses which don't specify a base
- Add libgeos-dev to Dockerfile

## v0.107.46, 4 June 2019

- Python: Sanitize poetry files before adding more details
- JS: Handle npmrc files with carriage returns in them

## v0.107.45, 4 June 2019

- Python: Correctly set Poetry sources from config variables (include a name)

## v0.107.44, 4 June 2019

- JS: Handle a bad body response from a custom registry

## v0.107.43, 4 June 2019

- Python: Raise helpful errors for unreachable git dependencies

## v0.107.42, 3 June 2019

- Go 1.12 support

## v0.107.41, 3 June 2019

- Handle deleted target branch when updating a PR

## v0.107.40, 3 June 2019

- If Bitbucket times out when getting commits, silence the error

## v0.107.39, 3 June 2019

- Add retries to Bitbucket client, and change initialize signature
- Python: Bump cython from 0.29.9 to 0.29.10

## v0.107.38, 1 June 2019

- Dep: Pass a dummy ref and branch

## v0.107.37, 1 June 2019

- Keep existing tag prefix when looking for local_tag_for_latest_version
- JS: Handle bad peer requirements

## v0.107.36, 1 June 2019

- Only consider first line when checking if commit prefixes should be capitalized
- Don't rely on dependabot[bot] name

## v0.107.35, 31 May 2019

- Python: Allow unchanged files in RequirementReplacer if req is unchanged

## v0.107.34, 31 May 2019

- Handle 451s instead of 403s from GitHub for blocked repos

## v0.107.33, 31 May 2019

- Handle blocked repositories when fetching commits and release notes

## v0.107.32, 31 May 2019

- Raise a BranchProtected error for protected branches (rather than silencing)

## v0.107.31, 31 May 2019

- Handle failed attempts to update protected branches

## v0.107.30, 31 May 2019

- Handle Octokit::UnavailableForLegalReasons errors when attempting to fetch changelogs
- Python: Remove private source checking from Pipenv and Poetry resolvers (done in LatestVersionFinder)
- Python: Include pyproject source in IndexFinder
- Python: Raise PrivateSourceTimedOut for timeouts in LatestVersionFinder

## v0.107.29, 31 May 2019

- Retry failures to fetch git repo in GitHub PR creator

## v0.107.28, 31 May 2019

- Cargo: Raise a resolvability error for submodule cloning issues
- Elm: Allow normal Ruby requirements in Elm::Requirement class
- Gradle: Raise DependencyFileNotFound error for missing dependency script plugins

## v0.107.27, 30 May 2019

- Python: Handle environment variables passed in place of basic auth details
- JS: Protect against non-string versions in package.json

## v0.107.26, 30 May 2019

- Terraform: Handle sub-dir reference in querystring
- Gradle: Ignore dependency script paths that need value interpolation

## v0.107.25, 29 May 2019

- Python: Preserve operator spacing
- Python: Remove duplication between RequirementReplacer and RequirementFileUpdater
- Python: Preserve whitespace in requirement.txt updates
- JS: Bump semver from 6.1.0 to 6.1.1 in /npm_and_yarn/helpers
- Extract issue linking logic into a separate class
- Python: Bump cython from 0.29.7 to 0.29.9 in /python/helpers

## v0.107.24, 28 May 2019

- Add php7.3-tidy to dockerfile

## v0.107.23, 26 May 2019

- Retry labeling failures caused by a race on the GitHub side

## v0.107.22, 26 May 2019

- Elixir: Better file sanitization

## v0.107.21, 26 May 2019

- Gradle: Ignore failure to fetch script plugins from submodules
- Python: Better python version error detection

## v0.107.20, 26 May 2019

- Python: Mark dependencies specified in a dev file as development dependencies

## v0.107.19, 25 May 2019

- Terraform: Handle unparseable files

## v0.107.18, 25 May 2019

- Gradle: Handle dynamic versions with minimum patch
- Python: Don't parse comments as part of index URL

## v0.107.17, 25 May 2019

- Python: Use configured git when using Poetry
- Ruby: Handle unevaluatable ruby versions

## v0.107.16, 24 May 2019

- JS: Bump tar from 2.2.1 to 2.2.2 in /npm_and_yarn/helpers

## v0.107.15, 24 May 2019

- Python: Handle unreachable git dependencies when using Poetry

## v0.107.14, 24 May 2019

- More retries for PR creation failures

## v0.107.13, 24 May 2019

- Elm: Raise a resolvability error for old versions of Elm
- JS: Bump semver from 6.0.0 to 6.1.0 in /npm_and_yarn/helpers

## v0.107.12, 20 May 2019

- Python: Don't accidentally replace extra declarations with locked versions

## v0.107.11, 20 May 2019

- Maven: Ignore unfetchable parents when finding repositories

## v0.107.10, 20 May 2019

- Raise an identifiable error if GitHub 500s during git metadata lookup

## v0.107.9, 18 May 2019

- Elixir: Cowardly fix for a mixfile updating issue

## v0.107.8, 18 May 2019

- Python: Run check_original_requirements_resolvable using correct Python version

## v0.107.7, 18 May 2019

- Maven: Ignore unfetchable parents
- Python: Bump poetry from 0.12.14 to 0.12.16

## v0.107.6, 16 May 2019

- Make Source#url dependant on hostname

## v0.107.5, 15 May 2019

- Allow custom headers to be passed to pull request creator
- Python: Don't fetch large .txt files

## v0.107.4, 15 May 2019

- Update dependencies label colour

## v0.107.3, 14 May 2019

- Bump dep

## v0.107.2, 13 May 2019

- JS: Ignore quotes in npmrc when looking for registry

## v0.107.1, 13 May 2019

- Python: Handle missing references for Poetry dependencies

## v0.107.0, 12 May 2019

- PHP: Update to minimal secure version for security updates

## v0.106.47, 12 May 2019

- Elixir: Sanitize config_path out of mixfiles

## v0.106.46, 10 May 2019

- Java: Handle branch not found errors in MetadataFinder

## v0.106.45, 10 May 2019

- Bundler: Update lockfiles which have tricky default gem handling

## v0.106.44, 10 May 2019

- JS: Bump @dependabot/yarn-lib from 1.15.2 to 1.16.0 in /npm_and_yarn/helpers
- Python: Bump pip-tools from 3.6.1 to 3.7.0 in /python/helpers

## v0.106.43, 9 May 2019

- Ruby: Better default when replacing file text

## v0.106.42, 9 May 2019

- JS: Handle packages without a name

## v0.106.41, 9 May 2019

- JS: Sanitize spaces in filenames

## v0.106.40, 9 May 2019

- Gradle: Fix VersionFinder for plugins that check maven.google.com

## v0.106.39, 9 May 2019

- Use service pack to determine existing branches

## v0.106.38, 8 May 2019

- Cache that a branch can't be found
- Don't cache a single branch_ref now that branch_exists? takes an argument

## v0.106.37, 8 May 2019

- Bundler: Always include spaces after commas

## v0.106.36, 8 May 2019

- Use updated branch name when creating PRs
- Python: Revert "Ignore irrelevant pyproject files to avoid pep517 warnings"

## v0.106.35, 7 May 2019

- Add longer sleep when creating a commit fails
- Python: Bump pip from 19.1 to 19.1.1 in /python/helpers
- Raise error for unprocessable branch names

## v0.106.34, 6 May 2019

- Python: Downgrade Poetry to avoid bug

## v0.106.33, 5 May 2019

- Bundler: Use --full-index when checking for updates and updating files

## v0.106.32, 3 May 2019

- Docker: Handle v1 dockerhub references

## v0.106.31, 3 May 2019

- Rename github_link_proxy to github_redirection_service
- Python: Don't prioritize Python 2 above lower Python 3 versions
- Python: Bump poetry from 0.12.14 to 0.12.15 in /python/helpers

## v0.106.30, 3 May 2019

- Python: Use python version indicated by markers in compiled pip-compile files
- Allow a custom GitHub link proxy to be provided to MessageBuilder
- Update Rust specs

## v0.106.29, 2 May 2019

- Handle issue linking of issue numbers prefixed with `\#`
- Don't sanitize @-mentions in code quotes

## v0.106.28, 1 May 2019

- Python: Handle sub-dependencies that are removed from the lockfile during update

## v0.106.27, 30 April 2019

- Allow a custom prefix to be passed to BranchNamer

## v0.106.26, 30 April 2019

- Gradle: Parse and update plugin versions

## v0.106.25, 30 April 2019

- Composer: Handle people putting strange things in their repositories hash/array
- Fix error-related rubocops

## v0.106.24, 29 April 2019

- Cargo: Handle private git dependencies that aren't parsed

## v0.106.23, 29 April 2019

- Python: Respect Python version specified in runtime.txt

## v0.106.22, 29 April 2019

- PHP: Fetch path dependencies specified in a hash (rather than an array)

## v0.106.21, 29 April 2019

- Python: Look for .python-version file at top-level, too

## v0.106.20, 28 April 2019

- Rust: Handle a resolvability issue
- Rust: Require a unique source (not just source type)
- Upgrade to PHP 7.3

## v0.106.19, 28 April 2019

- Python: Use Python 3.7.3 instead of 2.6.8
- Python: Bump poetry from 0.12.13 to 0.12.14 in /python/helpers

## v0.106.18, 26 April 2019

- Bump poetry from 0.12.12 to 0.12.13 in /python/helpers

## v0.106.17, 26 April 2019

- Update changelog finder to look in GitLab and Bitbucket directories, too
- Convert GitLab API types to match GitHub

## v0.106.16, 26 April 2019

- Sanitize all tags in commit messages

## v0.106.15, 26 April 2019

- Clean up tag sanitization and details tag creation

## v0.106.14, 26 April 2019

- Escape more tags when sanitizing lines
- Replace empty links (caused by rst processing)
- NPM: Remove extraneous git url fix

## v0.106.13, 26 April 2019

- Docker: Make self.updated_files_regex case insensitive

## v0.106.12, 25 April 2019

- NPM: Preserve indentation of lockfiles

## v0.106.11, 25 April 2019

- Python: Update to a specific version when updating Pipenv subdependencies
- Python: Update poetry sub-dependencies to a specific version
- Require minimum file size for changelogs

## v0.106.10, 25 April 2019

- Add php7.2-mysql providing pdo-mysql

## v0.106.9, 25 April 2019

- Add scope to fallback commit message
- Python: Ignore irrelevant pyproject files to avoid pep517 warnings
- Python: Bump pip from 19.0.3 to 19.1 in /python/helpers
- Python: Bump pip-tools from 3.6.0 to 3.6.1 in /python/helpers (#1120)

## v0.106.8, 24 April 2019

- NPM: Handle private registry error '403 Fobidden'
- JS: Handle git dependencies with file-path sub-dependencies

## v0.106.7, 24 April 2019

- Rust: Update target-specific dependencies

## v0.106.6, 24 April 2019

- Rust: Handle git dependencies changing version to a pre

## v0.106.5, 23 April 2019

- JS: Add floor to satisfying_versions in version resolver

## v0.106.4, 23 April 2019

- JS: Ignore aliased dependencies in lockfile parser

## v0.106.3, 23 April 2019

- Rust: Require a resolvable version, even when updating a library

## v0.106.2, 23 April 2019

- Ruby: Include a lower Ruby version in list of possible rubies (in case a < req specified)
- Add sleep before retrying commit creation

## v0.106.1, 22 April 2019

- Make commit prefixing more robust

## v0.106.0, 21 April 2019

- Pass old commit SHA when updating a PR, and use it to identify the relevant commit
- Composer: Add lowest_security_fix_version to LatestVersionFinder
- Composer: Refactor LatestVersionFinder to be more extensible
- Composer: Move tests for latest version finding to new class
- Composer: Extract latest_version logic into LatestVersionFinder class
- Composer: Stop passing latest_version to RequirementsUpdater (it was unused)
- Rust: Update to lowest fixed version for vulnerable dependencies
- Rust: Pass a single version to RequirementsUpdater

## v0.105.8, 19 April 2019

- Python: Handle subdependency resolution checking properly for pip-compile

## v0.105.7, 18 April 2019

- Stop using commit compare API endpoint when building commit diffs (it sometimes 500s)

## v0.105.6, 18 April 2019

- Python: Add `resolvable?` method to version resolvers, and use in update checkers

## v0.105.5, 18 April 2019

- JS: Handle cases where requirements stay identical except for switch to private source

## v0.105.4, 18 April 2019

- Ruby: Handle Ruby lock errors correctly in LockfileUpdater
- Ruby: Update versions constant

## v0.105.3, 18 April 2019

- Python: Handle lockfile-only updates with an unrelated requirement
- Rust: Tell rustup to use cURL
- Rust: Change ownership of /opt/rust in dev dockerfile

## v0.105.2, 18 April 2019

- Rust: Add LatestVersionFinder#lowest_security_fix_version
- Rust: Extract specs for LatestVersionFinder
- Rust: Extract latest version finder logic into separate class

## v0.105.1, 17 April 2019

- JS: Handle MyGet format resolved URLs

## v0.105.0, 17 April 2019

- Python: Update to lowest fix for security vulnerabilities (all package managers)

## v0.104.6, 17 April 2019

- Python: Refactor PipCompileVersionResolver to match other resolvers
- Python: Refactor PoetryVersionResolver to match PipenvVersionResolver
- Python: Refactor PipenvVersionResolver#latest_resolvable_version to take a
  requirement arg
- Python: Refactor PipenvVersionResolver to make it more extensible
- PHP: Re-remove Xdebug

## v0.104.5, 17 April 2019

- Add back x-debug

## v0.104.4, 17 April 2019

- JS: Handle package.json files that specify an array of dependencies (not an object)

## v0.104.3, 17 April 2019

- Remove xdebug from container
- Rename pipfile resolver to pipenv

## v0.104.2, 17 April 2019

- Python: Refactor UpdateChecker to make it more extensible
- Python: Rename PipfileVersionResolver to PipenvVersionResolver
- Python: Update to lowest fixed version for vulnerable requirement.txt versions
- Python: Add lowest_security_fix_version to UpdateChecker::LatestVersionFinder
- Python: Pass security_advisories to LatestVersionFinder

## v0.104.1, 17 April 2019

- Add mercurial to Dockerfile
- Ruby: Minor efficiency improvement in LatestVersionFinder
- Python: Refactor LatestVersionFinder to make private methods easier to reuse
- Add tests for Python::UpdateChecker::IndexFinder
- Python: Split index finder logic into separate class
- More simplification of Bundler::UpdateChecker
- Clean up Bundler::UpdateChecker::LatestVersionFinder

## v0.104.0, 16 April 2019

- Ruby: Update to minimal version possible for security updates

## v0.103.3, 14 April 2019

- Python: Fix handling of comparisons with non-canonical segments

## v0.103.2, 14 April 2019

- Python: Support pre-releases in wildcards, and allow Python 3.8-dev

## v0.103.1, 14 April 2019

- Composer: Build path dependencies from lockfile even when whole dir is missing

## v0.103.0, 14 April 2019

- Require a dependency_name when creating a SecurityAdvisory
- Python: Bump cython from 0.29.6 to 0.29.7

## v0.102.1, 12 April 2019

- JS: Don't assume we can upgrade sub-dependencies to a secure version

## v0.102.0, 12 April 2019

- JS: Update insecure dependencies to the minimum secure version

## v0.101.2, 12 April 2019

- Nuget: support lowercase version attributes
- JS: Pass security advisories to LatestVersionChecker

## v0.101.1, 12 April 2019

- JS: Fix update checker for deprecated deps

## v0.101.0, 12 April 2019

- Gradle: Upgrade to lowest fixed version if a dependency is vulnerable
- .NET: Upgrade to lowest fixed version if a dependency is vulnerable
- Maven: Upgrade to lowest fixed version if a dependency is vulnerable
- Maven: Cache release checks

## v0.100.2, 12 April 2019

- Ignore closed PR errors when updating a PR's branch

## v0.100.1, 12 April 2019

- Don't re-cast versions to versions in SecurityAdvisory

## v0.100.0, 12 April 2019

- Bump poetry from 0.12.11 to 0.12.12 in /python/helpers
- Add SecurityAdvisory class, used in UpdateCheckers::Base to determine if a
  version is vulnerable
- NPM: Remove dry-run config setting
- Add UpdateCheckers::Base#vulnerable? method, which checks against security advisories
- Accept a security_advisories argument to UpdateCheckers::Base.new

## v0.99.7, 10 April 2019

- JS: Handle build metadata in version strings

## v0.99.6, 10 April 2019

- Gradle: Handle commented out lines when updating files
- Python: Handle wildcards in requirements with a non-equality operator

## v0.99.5, 10 April 2019

- .NET: Treat dependency names as case-insensitive

## v0.99.4, 10 April 2019

- PHP: Bump composer/composer from 1.8.4 to 1.8.5

## v0.99.3, 9 April 2019

- Handle deleted target branches when creating a PR
- Python: Use pyenv v1.2.11 in Dockerfile, and update available Python versions

## v0.99.2, 9 April 2019

- Nuget: support multiple .sln files

## v0.99.1, 8 April 2019

- Git submodules: Raise parser error for trailing slashes in path

## v0.99.0, 5 April 2019

- NPM: Fix "premature close" for git dependencies

## v0.98.78, 5 April 2019

- Gradle: Better PROPERTY_REGEX

## v0.98.77, 5 April 2019

- Python: Raise error for invalid poetry requirements
- Ruby: Ignore Bundler updates if requirement is non-trivial
- Python: Bump pip-tools from 3.5.0 to 3.6.0 in /python/helpers

## v0.98.76, 4 April 2019

- NPM: Fix git dependencies with invalid requires

## v0.98.75, 4 April 2019

- JS: Handle invalid requirements better, and ignore rogue equal signs
- Docker: Treat RestClient::Exceptions::ReadTimeout exceptions the same as RestClient::Exceptions::OpenTimeout

## v0.98.74, 4 April 2019

- Better GitHub link replacement
- Maven: Handle requirements which include underscores

## v0.98.73, 4 April 2019

- Ruby: Don't ignore all > requirements in ForceUpdater
- Ruby: Only consider relevant conflicts when unlocking additional deps

## v0.98.72, 3 April 2019

- Maven: Include http:// version of central registry in special handling

## v0.98.71, 2 April 2019

- Docker: make ECR requests work w/o credentials

## v0.98.70, 2 April 2019

- Ruby: Always evaluate files from within a base directory

## v0.98.69, 2 April 2019

- Cargo: Handle additional error type that represents an unreachable git repo

## v0.98.68, 2 April 2019

- Yarn: ignore platform check

## v0.98.67, 2 April 2019

- PHP: Move back to clearer memory limit setting

## v0.98.66, 2 April 2019

- NPM: ignore prepare and prepack scripts when installing git dependencies

## v0.98.65, 2 April 2019

- Add fallback PHP environment variable

## v0.98.64, 2 April 2019

- Docker: Handle invalid file encoding

## v0.98.63, 1 April 2019

- Add an automerge label to automerge candidates if one is present

## v0.98.62, 1 April 2019

- JS: Look for dependency details in a lockfile that might match this manifest (not any lockfile)

## v0.98.61, 1 April 2019

- Revert "Bundler: Include protocol when raising PrivateSourceAuthenticationFailure errors"

## v0.98.60, 1 April 2019

- Bump semver from 5.6.0 to 6.0.0 in /npm_and_yarn/helpers

## v0.98.59, 1 April 2019

- Maven: Better dot separator regex in PropertyValueFinder

## v0.98.58, 1 April 2019

- JS: Don't mistake v-prefixed versions for distribution tags

## v0.98.57, 1 April 2019

- Python: Case insensitive check for whether dependency name is in error message

## v0.98.56, 1 April 2019

- JS: Ignore 500s from private registries
- .NET: Handle property versions that reference a function

## v0.98.55, 31 March 2019

- JS: Handle npm lockfile name substitution in post-processing

## v0.98.54, 31 March 2019

- JS: Don't replace package name when generating updated npm lockfile

## v0.98.53, 30 March 2019

- Python: Handle environment variables for Gemfury URLs

## v0.98.52, 29 March 2019

- Pass empty string token to elixir helper, again

## v0.98.51, 30 March 2019

- Ruby: Include protocol when raising PrivateSourceAuthenticationFailure errors
- Elixir: Pass empty string token to elixir helper
- JS: Better registry uniq-ing

## v0.98.50, 29 March 2019

- Bundler: Handle resolver returning `nil` for an unchanged git source

## v0.98.49, 28 March 2019

- Handle missing token in js registry finder

## v0.98.48, 29 March 2019

- Don't attempt to configure git creds that don't have a username or password

## v0.98.47, 28 March 2019

- Python: Handle basic auth credentials that include an `@` in the username

## v0.98.46, 28 March 2019

- NPM: Optionally build npmrc without credentials

## v0.98.45, 28 March 2019

- Bundler: Handle repos without a lockfile where the dep being updated has an implicit pre-release requirement

## v0.98.44, 27 March 2019

- Python: Fetch requirement files with lines that start with a comment

## v0.98.43, 27 March 2019

## v0.98.42, 27 March 2019

- Bump @dependabot/yarn-lib from 1.13.0 to 1.15.2 in /npm_and_yarn/helpers

## v0.98.41, 26 March 2019

- Python: Handle yanked dependencies in PoetryVersionResolver
- Python: Better environment variable support in LatestVersionFinder
- Fix rubocop

## v0.98.40, 26 March 2019

- Python: Handle environment variables in LatestVersionFinder

## v0.98.39, 26 March 2019

- Python: Fix copy-paste error

## v0.98.38, 26 March 2019

- Bundler: Handle tricky ruby requirements in a gemspec when generating new lockfiles

## v0.98.37, 26 March 2019

- Python: Handle errors due to updating a dep to a version with a Python requirement issue (poetry)
- Add handling for tree creation race to pull request updater

## v0.98.36, 26 March 2019

- Handle unexpected previous versions in CommitsFinder

## v0.98.35, 25 March 2019

- Bundler: Don't add .rb suffix to require_relative files that already include it

## v0.98.34, 25 March 2019

- Python: Don't include dependencies parsed from a req.txt that are also included in Poetry
- Maven: Better file update regex (trust declaration finder more)
- JS: try/catch helper scripts

## v0.98.33, 25 March 2019

- Yarn: install specific sub-dependency version

## v0.98.32, 25 March 2019

- Composer: Serve resolvability error if required connections are disallowed
- Allow config variables without credentials wherever possible

## v0.98.31, 22 March 2019

- Python: Allow credentials to be passed with a token
- Use Bitbucket client in GitCommitChecker
- Use GitLab client when doing commit comparison

## v0.98.30, 22 March 2019

- Python: Reorganize FileUpdater#resolver_type to better handle cases where req.txt needs updating
- Python: More marker parsing improvements
- Python: Better handling of markers in requirements.txt

## v0.98.29, 22 March 2019

- Composer: Correct name for path deps starting with ../
- Yarn: handle git dependencies with token

## v0.98.28, 22 March 2019

- .NET: More sophisticated property value updater

## v0.98.27, 21 March 2019

- Maven: Handle repeated dependency declarations with different scopes

## v0.98.26, 21 March 2019

- Python: Handle updating Pipfiles which declare a version in a table

## v0.98.25, 21 March 2019

- Python: Split Pipfile manifest updater into separate class
- Use GitHub repo name defintion for GitLab and Azure
- PHP: Handle relative paths that are actually from the root
- Rebuild Dockerfile using Ruby 2.6.2

## v0.98.24, 21 March 2019

- Ruby: Update list of latest rubies
- Python: Normalise dependency names when looking for them in poetry lockfile
- Do two retries when attempting to fetch git metadata
- Maven: Handle case where declaration_pom_name isn't found

## v0.98.23, 21 March 2019

- Python: Handle v-prefixes in versions and requirements

## v0.98.22, 21 March 2019

- PHP: Update memory limit setting again

## v0.98.21, 20 March 2019

- Python: refactor escaped command string
- Dep: escape command
- Cargo: escape command
- Fix escaped command for composer
- Escape shared helpers run subprocess cmd by default

## v0.98.20, 20 March 2019

- Python: Use original manifest instead of original compiled file when unredacting creds if required

## v0.98.19, 20 March 2019

- Python: Handle git credentials getting redacted as part of pip-compile install process
- Go: Retry transitory Go resolution issues
- Python: Remove unnecessary install

## v0.98.18, 20 March 2019

- Rust: Fetch patched path dependencies

## v0.98.17, 19 March 2019

- Use updated (clearer) style in other PHP helper

## v0.98.16, 19 March 2019

- Use Dependabot::Clients::GitlabWithRetries.for_source in labeler
- Python: Use 2.7.16
- Python: Use latest pyenv commit to get Python 2.7.16

## v0.98.15, 19 March 2019

- Python: Raise a DependencyFileNotResolvable error for unsupported pip-compile constraints

## v0.98.14, 19 March 2019

- Python: Use build isolation in FileUpdater
- Assume closing index of 0 if one can't be found
- Add test to ensure build-isolation not required in Python file updater

## v0.98.13, 19 March 2019

- Python: Build in isolation when using pip-tools (to prevent errors when using a pyproject.toml)

## v0.98.12, 19 March 2019

- Use php7.2-zmq instead of php-zmq

## v0.98.11, 19 March 2019

- .NET: Only update pre-release versions to pre-s for the same version
- Docker: Tighter regex for updating version

## v0.98.10, 18 March 2019

- Python: Don't escape spaces in pip-compile options

## v0.98.9, 18 March 2019

- Gradle: Handle multiple updates to a superstring
- .NET: Raise parser error for unparseable JSON

## v0.98.8, 18 March 2019

- Python: escape child process commands

## v0.98.7, 18 March 2019

- Stricter regex for Python file correctness

## v0.98.6, 18 March 2019

- Python: Better regex for dependency names
- Remove redundant require

## v0.98.5, 17 March 2019

- PHP: Remove overzealous use of shellwords

## v0.98.4, 16 March 2019

- Gradle: Handle property declarations in namespaces
- Gradle: Minor cleanup (uniq files)

## v0.98.3, 16 March 2019

- .NET: Update NuGet packages in global.json

## v0.98.2, 15 March 2019

- Docker: Raise custom error when private registries time out fetching tags

## v0.98.1, 15 March 2019

- Sign commits on behalf of an org
- Add support_file to DependencyFile#to_h

## v0.98.0, 15 March 2019

- Python: Avoid shelling out to Python during file fetching
- JS: Don't shell out to JavaScript during file fetching
- Ruby: Remove all calls to eval from file fetching

## v0.97.11, 15 March 2019

- JS: Fix native helper path in development and test

## v0.97.10, 14 March 2019

- Cargo: Remove lockfile duplicates

## v0.97.9, 14 March 2019

- Revert changes to JS helpers in dev and test env

## v0.97.8, 14 March 2019

- Handle 409s from GitHub when constructing commit message
- JS: Use un-built helpers in development and test env

## v0.97.7, 13 March 2019

- Short circuit update checking for dependencies being ignored

## v0.97.6, 13 March 2019

- NPM: Raise helpful error when lockfile is corrupt
- Bump pip-tools from 3.4.0 to 3.5.0 in /python/helpers
- Bump jest from 24.4.0 to 24.5.0 in /npm_and_yarn/helpers

## v0.97.5, 11 March 2019

- Elm: clean up subprocess invocation

## v0.97.4, 11 March 2019

- Dep: clean up subprocess invocation
- Composer: clean up subprocess invocation
- Cargo: clean up subprocess invocation
- Go (modules): clean up subprocess invocations

## v0.97.3, 10 March 2019

- Prefer non-app github.com token in SharedHelpers.configure_git_credentials
- Handle invalid milestones quietly

## v0.97.2, 7 March 2019

- Ignore 404s when attempting to set assignees
- JS: Bump npm from 6.8.0 to 6.9.0 in /npm_and_yarn/helpers

## v0.97.1, 5 March 2019

- Handle tags that match our version regex but don't have valid versions
- Bundler: Handle marshall errors

## v0.97.0, 5 March 2019

- Composer: Install php7.2-gmp
- Bundler: Bump rubygems from 3.0.2 to 3.0.3
- JS: Bump eslint from 5.14.1 to 5.15.1 in /npm_and_yarn/helpers

## v0.96.1, 4 March 2019

- Go (modules): handle another case of module path mismatches

## v0.96.0, 4 March 2019

- Minor version bump to signify that JS refactor (included in v0.95.85) is a
  breaking change, as it requires an update to the Dockerfile as well as the
  gem

## v0.95.85, 4 March 2019

- Fix gitignore for npm and yarn helpers
- JS: Ignore URL-style versions in npm lockfiles in NpmAndYarn::FileParser::LockfileParser
- Ruby: Handle marshal dump errors more gracefully
- Composer: Automatically retry transitory errors in VersionResolver
- Add php-zmq to Dockerfile
- JS: Simplify helper usage to only one script (#988)

## v0.95.84, 2 March 2019

- Better tag comparison in CommitsFinders
- Ruby: Handle circular dependencies at the latest version
- Terraform: Parse `git@github.com:` module sources

## v0.95.83, 28 February 2019

- JS: Fetch numeric version for git dependencies with a semver requirement
- Python: Handle .zip or .whl suffices in LatestVersionFinder
- Python: Bump cython from 0.29.5 to 0.29.6 in /python/helpers

## v0.95.82, 28 February 2019

- Prefer refs to versions when generating compare URLs for git updates

## v0.95.81, 27 February 2019

- Python: Raise a resolvability error for Python version conflicts when Python version is user-defined
- Go (modules): switch back to mastermind/vsc now 1.13 is out

## v0.95.80, 27 February 2019

- Ruby: Fix gemspec sanitizer, and update test to have a Gem::Version

## v0.95.79, 27 February 2019

- Ruby: Alternative approach to sanitizing version constants in gemspecs
- Ruby: Only sanitize versions when they appear in strings

## v0.95.78, 27 February 2019

- JS: Treat projects with invalid names as non-library

## v0.95.77, 27 February 2019

- Python: handle fetching whl files dependencies

## v0.95.76, 27 February 2019

- Ruby: Handle more gemspec sanitization

## v0.95.75, 27 February 2019

- Ruby: More gemspec sanitization
- PHP: Build path dependencies from lockfile if not fetchable

## v0.95.74, 26 February 2019

- Go (modules): prevent all pseudo version updates
- Dockerfile: Add bzr to the Dockerfile

## v0.95.73, 26 February 2019

- NPM: Fix lockfile for git deps with semver version

## v0.95.72, 26 February 2019

- Handle TomlRB::ValueOverwriteError everywhere we handle TomlRB::ParseError

## v0.95.71, 26 February 2019

- Rust: Handle TomlRB::ValueOverwriteError errors in FileParser
- Rust: Handle parse errors in unprepared files in VersionResolver

## v0.95.70, 26 February 2019

- Retry GitLab 502s everywhere

## v0.95.69, 25 February 2019

- Ruby: Handle pre-releases with numeric parts in the pre-release specifier

## v0.95.68, 25 February 2019

- Fix handling of docker dependencies in ChangelogFinder

## v0.95.67, 25 February 2019

- Maven: Treat dependencies that specify their scope as `test` as development dependencies

## v0.95.66, 25 February 2019

## v0.95.65, 25 February 2019

- JS: Fix peer dependency updates for libraries

## v0.95.64, 25 February 2019

- JS: Return a version instance from UpdateChecker#latest_resolvable_version_with_no_unlock when version is numeric

## v0.95.63, 25 February 2019

- JS: Handle non-JSON responses from private registries when checking git deps
- JS: Handle duplicate peer dependency error

## v0.95.62, 25 February 2019

- Fix changelog fetching with a suggested changelog URL and no source
- PHP: Automatically retry transitory errors in lockfile updater
- Ruby: Better requirement string parsing

## v0.95.61, 23 February 2019

- Python: Fix python version installed check
- Use Ruby 2.6.1

## v0.95.60, 23 February 2019

- Python: Be explicit about the python version being installed

## v0.95.59, 23 February 2019

- Python: Better Python version handling for Pipenv
- Python: List supported versions, and error if using an unsupported one
- Bump pyenv, Go and Elixir versions in Dockerfile

## v0.95.58, 22 February 2019

- Go (modules): tighten up error regex

## v0.95.57, 22 February 2019

- Go (modules): Handle module path mismatch errors

## v0.95.56, 22 February 2019

- NPM: Fix missed lerna peer dependency update
- Reduce robocop config spread and cover root files

## v0.95.55, 22 February 2019

- Python: Use user's defined Python version when compiling pip-compile files
- Retry GitHub races when creating a commit from a new tree

## v0.95.54, 21 February 2019

- Python: Treat install_requires dependencies as production dependencies
- Ruby: Don't mistake support files for evaled gemfiles

## v0.95.53, 21 February 2019

- Go (modules): handle missing sub-dependency error

## v0.95.52, 21 February 2019

- Ruby: Implement suggested_changelog_url, based on changelog_uri in gemspec
- Add suggested_changelog_url method to MetadataFinder::Base, that is passed to
  ChangelogFinder
- Python: Bump pip from 19.0.2 to 19.0.3 in /python/helpers

## v0.95.51, 20 February 2019

- NPM: Sanitise extra trailing slash from private registries
- Python: Don't repeatedly parse Pipfile.lock

## v0.95.50, 20 February 2019

- Python: Fetch poetry path dependencies
- Python: Only parse large lockfiles once

## v0.95.49, 20 February 2019

- Ruby: Handle another gem not found error case

## v0.95.48, 20 February 2019

- JS: Actually special case DefinitelyTyped

## v0.95.47, 20 February 2019

- JS: Don't update source from git to registry just because version isn't a SHA
- JS: Include a leading `*` as a semver indicator
- Python: Bump pip-tools from 3.3.2 to 3.4.0 in /python/helpers
- Ruby: Allow gemspec dependencies to have a source (in case it's git)

## v0.95.46, 19 February 2019

- Cargo: fix git credential helper issue

## v0.95.45, 19 February 2019

- .NET, Ruby and Rust: Fix directory handling for deeply nested file fetching

## v0.95.44, 19 February 2019

- Reverse commits when building a monorepo compare URL

## v0.95.43, 19 February 2019

- JS: Better special casing for gatsby
- Python: Look in project_urls for homepage
- PHP: Use the global variable $memory when freeing it

## v0.95.42, 19 February 2019

- Rust: Handle non-existent packages

## v0.95.41, 19 February 2019

- Simpler tag sorting for finding most appropriately named tag

## v0.95.40, 19 February 2019

- Better commit fetching for monorepos
- Always prefer commits URL with path for monorepos

## v0.95.39, 19 February 2019

- NPM: Fix lockfile for git dependencies using tags

## v0.95.38, 19 February 2019

- Better lowest_tag_satisfying_previous_requirements lookup

## v0.95.37, 18 February 2019

- Fetch git tags from git upload pack, rather than APIs, in CommitsFinder
- Speed up GitCommitChecker tag processor

## v0.95.36, 18 February 2019

- JS: Add special cases for Gatsby and DefinitelyTyped repos

## v0.95.35, 18 February 2019

- NPM: Speed up sub-dependency updates for big lerna projects using npm
- Composer: Bump friendsofphp/php-cs-fixer from 2.14.1 to 2.14.2 in /composer/helpers

## v0.95.34, 17 February 2019

- JS: Include details of directory in source if included in repository object
- Append directory to source URL when reliable
- Include directory details in commits URL if reliable
- Make source attributes editable, and add Source#url_with_directory method

## v0.95.33, 16 February 2019

- JS: Only assign a single credential to a scope in npmrc builder

## v0.95.32, 15 February 2019

- Ruby: Update version requirement at the same time as updating git tag

## v0.95.31, 15 February 2019

- JS: Parse full nexus private repository URLs from lockfile entries for scoped dependencies

## v0.95.30, 15 February 2019

- JS: Better handling of incorrect credentials for a private registry
- Better commit comparison links for dependencies without a previous version

## v0.95.29, 15 February 2019

- Fetch files from symlinked directories if fetching submodules

## v0.95.28, 14 February 2019

- Go (modules): more detailed error messages for unresolvable dependencies due
  to git errors, and for go.sum checksum mismatches.

## v0.95.27, 14 February 2019

- NPM: Prefer offline cache and turn off audits

## v0.95.26, 14 February 2019

- Go (modules): detect and handle missing/invalid dependency specified with
  pseudo version

## v0.95.25, 14 February 2019

- Cargo: Include all unreachable git dependencies when raising GitDependenciesNotReachable
- Fix time taken measurement for shell cmds
- Add git_repo_reachable? method to GitCommitChecker

## v0.95.24, 14 February 2019

- Cargo: Handle unreachable git dependencies

## v0.95.23, 14 February 2019

- Another @-mention sanitization improvement (better regex)
- JS: Bump npm from 6.7.0 to 6.8.0 in /npm_and_yarn/helpers

## v0.95.22, 14 February 2019

- Cleaner mention sanitizing (use a zero width character)

## v0.95.21, 14 February 2019

- Better sanitization of @mentions when wrapped in a link

## v0.95.20, 13 February 2019

- Update issue tag regex

## v0.95.19, 13 February 2019

- Add optional dependency on Pandoc that allows us to convert rst files

## v0.95.18, 13 February 2019

- PHP: Handle integer versions in composer.lock
- Add .gitignore
- Base: Convert directory to proper path before using it in file fetchers

## v0.95.17, 12 February 2019

- Python: Dig into source URL looking for reference to dependency name
- Gradle: Handle $rootDir variable in dependency script plugins

## v0.95.16, 12 February 2019

- Common: include bin files in dependabot-common packaged gem
- Require common in dry run script

## v0.95.15, 12 February 2019

- Sanitize @-mentions that are prefixed with a dash

## v0.95.14, 12 February 2019

- Python: Don't try to update 'empty' requirements.txt files as part of a Pipfile update
- PHP: Bump composer/composer from 1.8.3 to 1.8.4 in /composer/helpers
- Python: Check source project_url for a GitHub link in MetadataFinder

## v0.95.13, 11 February 2019

- Better branch naming when updating multiple deps

## v0.95.12, 11 February 2019

- JS: Handle registries that don't escape slashes in dependency names except at /latest

## v0.95.11, 11 February 2019

- Gradle: Fetch plugin script files, and update them
- PHP: Handle another error

## v0.95.10, 11 February 2019

- Python: Bump pip from 19.0.1 to 19.0.2 in /python/helpers
- Python: Bump cython from 0.29.4 to 0.29.5 in /python/helpers

## v0.95.9, 10 February 2019

- Rust: Fix method name typo

## v0.95.8, 10 February 2019

- Rust: Fix over-eager manifest file updating
- JS: Better handling of multiple git requirements

## v0.95.7, 8 February 2019

- Bundler: fix gemspec since 1ddf668

## v0.95.6, 8 February 2019

- Go (modules): handle vanity urls that return non-200 responses
- Bundler: remove unnecessary helpers

## v0.95.5, 8 February 2019

- Paginate through GitLab labels
- Python: Make post version comparison logic more explicit

## v0.95.4, 8 February 2019

- Python: Fix bug in post release version comparison

## v0.95.3, 8 February 2019

- Ruby: Handle assignment to hash attributes in sanitizer

## v0.95.2, 7 February 2019

- Fix common gemspec

## v0.95.1, 7 February 2019

- Python: Handle post-release versions properly

## v0.95.0, 7 February 2019

- PHP: Handle version requirements with a trailing dot
- Move shared code to a new `dependabot-common` gem
- Bump gitlab from 4.8 to 4.9
- Align GitLab PR creator with generic options

## v0.94.13, 7 February 2019

- Handle target branches that are a substring

## v0.94.12, 6 February 2019

- Python: Fetch vendored .zip files

## v0.94.11, 6 February 2019

- Correct relative links from GitHub release notes

## v0.94.10, 5 February 2019

- Cargo: Better spec construction

## v0.94.9, 5 February 2019

- Docker: Handle tags with both a prefix and a suffix

## v0.94.8, 4 February 2019

- Cargo: More specific details of dependency being updated

## v0.94.7, 3 February 2019

- Add php-mongodb to Dockerfile

## v0.94.6, 3 February 2019

- Raise normal error when submodule source isn't supported

## v0.94.5, 3 February 2019

- JS: Look for login form redirects, not 404s, when checking packages on npmjs.com

## v0.94.4, 3 February 2019

- Fetch files that are nested in submodules if asked
- Clean up file fetcher base class

## v0.94.3, 2 February 2019

- Better name for language label details

## v0.94.2, 2 February 2019

- Add class attribute_reader to Labeler
- Ruby: Move bundler monkey patches
- Python: Bump cython from 0.29.3 to 0.29.4 in /python/helpers

## v0.94.1, 1 February 2019

- Add bundler to omnibus

## v0.94.0, 1 February 2019

- Reorg bundler

## v0.93.17, 1 February 2019

- JS: Better detection of whether an npm registry needs auth
- Increase max retries for GitHub client
- Python: Bump hashin from 0.14.4 to 0.14.5 in /python/helpers

## v0.93.16, 31 January 2019

- Go: Retry resolvability errors in parser

## v0.93.15, 31 January 2019

- Python: Handle Poetry solver problems

## v0.93.14, 31 January 2019

- Add workaround for GitHub bug during PR creation
- PHP: Bump composer/composer from 1.8.2 to 1.8.3 in /composer/helpers
- Python: Bump hashin from 0.14.2 to 0.14.4 in /python/helpers

## v0.93.13, 30 January 2019

- .NET: Handle Nuget sources that don't return a ProjectUrl

## v0.93.12, 30 January 2019

- JS: Return a NpmAndYarn::Version, not a string, for git semver dependencies
- PHP: Bump composer/composer from 1.8.0 to 1.8.2 in /composer/helpers

## v0.93.11, 29 January 2019

- Gradle: Handle tabs when looking for repositories

## v0.93.10, 29 January 2019

- JS: Parse the semver version, rather than the git SHA, for git reqs with a semver specification

## v0.93.9, 29 January 2019

- Python: Handle Apache Airflow 1.10.x installs with pip-compile

## v0.93.8, 29 January 2019

- Maven: Update dot separator regex

## v0.93.7, 28 January 2019

- Python: Fix sanitization and remove puts calls

## v0.93.6, 28 January 2019

- Python: Sanitize # symbols in pyproject.toml files
- Python: Bump pip-tools from 3.3.1 to 3.3.2 in /python/helpers

## v0.93.5, 27 January 2019

- Maven: Handle case where property value can't be found in MetadataFinder

## v0.93.4, 27 January 2019

- Maven: Substitute properties in the URL when fetching a parent POM file

## v0.93.3, 27 January 2019

- Python: Handle fetching gzipped path dependencies

## v0.93.2, 26 January 2019

- Python: Handle Poetry sub-deps that should be removed from the lockfile
- JS: Fix bug when updating npm@5 lockfile w/ npm@6.6.0

## v0.93.1, 25 January 2019

- Merge branch 'fix-js-helper-location'
- Log when CIRCLE_COMPARE_URL isn't set
- Rubocop
- Fix JS helper location
- Merge branch 'hex-build-script-fix'
- Fix hex build script
- Revert "Revert "Make hex helpers obey install_dir""

## v0.93.0, 25 January 2019

- Python: Bump pip from 18.1 to 19.0.1 in /python/helpers
- Python: Bump pip-tools from 3.1.0 to 3.3.1 in /python/helpers

## v0.92.8, 24 January 2019

- Python: Fix for post-processing compiled files with reordered indices
- JS: Bump npm from 6.6.0 to 6.7.0 in /npm_and_yarn/helpers

## v0.92.7, 24 January 2019

- Make python helpers obey install_dir
- Make npm_and_yarn build script obey install_dir

## v0.92.6, 23 January 2019

- Python: Use poetry update [dep-name] --lock when updating Poetry files

## v0.92.5, 22 January 2019

- Ruby: CGI escape credentials before passing to Bundler
- PHP: Clean Composer programmatically install

## v0.92.4, 22 January 2019

- Rust: Raise PathDependenciesNotReachable errors, rather than
  DependencyFileNotFound errors

## v0.92.3, 22 January 2019

- JS (npm): Fix invalid from for git sub-dependencies
- Reduce "running as root" warnings with Docker image

## v0.92.2, 21 January 2019

- Update .gitignore

## v0.92.1, 21 January 2019

- Update gitignore for npm_and_yarn helpers move

## v0.92.0, 21 January 2019

- .NET, Elixir and Python: Better handling of version with build/local part
- JS: Simplify npm_and_yarn helpers to yarn workspaces
- JS: Bump npm from 6.5.0 to 6.6.0 in /npm_and_yarn/helpers/npm
- JS: Handle sub-dep version resolution errors
- Python: Bump cython from 0.29.2 to 0.29.3 in /python/helpers
- Python: Bump hashin from 0.14.1 to 0.14.2 in /python/helpers

## v0.91.8, 20 January 2019

- JS: Add support for Yarn git semver
- PHP: Always pass to json_encode for secure output
- PHP: Switch to a real helper bin file

## v0.91.7, 20 January 2019

- .NET: Handle build versions

## v0.91.6, 20 January 2019

- Add php7.2-apcu to Dockerfile

## v0.91.5, 18 January 2019

- Python: Fetch cascading requirement.in files
- Better commit subject truncation

## v0.91.4, 17 January 2019

- Docker: Handle AWS auth errors

## v0.91.3, 17 January 2019

- Raise NoHistoryInCommon error if it blocks PR creation

## v0.91.2, 17 January 2019

- JS: Stop registering the wrong version class

## v0.91.1, 17 January 2019

- JS: Memoize lockfile updates
- JS: Only include relevant dependency files when updating files

## v0.91.0, 17 January 2019

- JS: Reorganise into npm_and_yarn directory
- Elixir: require fully released version of jason
- Remove possibly redundant check that npm lockfile has changed
- JS: Add error context when no files where updated
- Update license to 2.0
- Fix README typo
- Dep: Ignore indirect dependencies in latest_resolvable_version_with_no_unlock

## v0.90.7, 15 January 2019

- Dep: Ignore indirect dependencies more robustly
- .NET: Even longer timeout

## v0.90.6, 14 January 2019

- Handle git to registry PRs for libraries in PR message builder

## v0.90.5, 14 January 2019

- Fix typo

## v0.90.4, 14 January 2019

- Rust: Handle old version of resolution failure error (for when toolchain specified)
- Use Elixir 1.8.0

## v0.90.3, 14 January 2019

- PHP: Handle registries that 404 on /packages.json

## v0.90.2, 14 January 2019

- Docker: Simplify updated_digest fetching, and retry DockerRegistry2::NotFound on tags
- Rust: Handle no latest_version when updating a library

## v0.90.1, 14 January 2019

- NPM: Handle package name with invalid characters

## v0.90.0, 14 January 2019

- Python: Bump poetry from 0.12.10 to 0.12.11 in /python/helpers
- Reorg dep

## v0.89.5, 13 January 2019

- .NET: Handle wildcard requirements without any digits

## v0.89.4, 12 January 2019

- Handle 403 forbidden responses from Bitbucket

## v0.89.3, 12 January 2019

- Ruby: Handle fetching gemspecs which specify a path

## v0.89.2, 11 January 2019

- Require composer from omnibus
- Update README for refactor install instructions
- PHP: Handle blank responses from registries
- Add composer to Dockerfile.ci and loadpath in dry-run

## v0.89.1, 11 January 2019

- Add missing requires

## v0.89.0, 11 January 2019

- PHP reorg
- Change subprocess IO.popen to Open3.capture2
- Add error context when helper subprocesses fail

## v0.88.3, 10 January 2019

- Ruby: Add Ruby 2.6.0 to list of rubies in RubyRequirementSetter
- Handle git dependencies when creating PR message for libraries

## v0.88.2, 10 January 2019

- JS: Handle ~ and ^ version requirements with blank minor.patch version

## v0.88.1, 9 January 2019

- Better handling of directories in changelog finder

## v0.88.0, 9 January 2019

- Elixir reorg

## v0.87.15, 9 January 2019

- PHP: Raise resolvability issue when working with local VCS errors
- Bump @dependabot/yarn-lib from 1.12.3 to 1.13.0 in /helpers/yarn

## v0.87.14, 9 January 2019

- Handle Bitbucket 401s during changelog lookup
- Handle Bitbucket 401s during commit lookup

## v0.87.13, 7 January 2019

- Cargo: If a file is both a support_file and a dependency file, treat as a dependency file only

## v0.87.12, 7 January 2019

- Cargo: Handle aliased dependencies better in file preparer
- Ruby: Handle subdependency updates when the subdep gets removed

## v0.87.11, 7 January 2019

- PHP: Cowardly ignore of stefandoorn/sitemap-plugin error we can't figure out
- PHP: Serve resolution error for non-https requests when they're disallowed
- PHP: Improve memory limit handling in PHP helper

## v0.87.10, 6 January 2019

- Better GitHub issue sanitization
- Gradle: Handle packaging types in versions

## v0.87.9, 5 January 2019

- Elixir: Handle whitespace before commas when updating mixfiles

## v0.87.8, 4 January 2019

- Python: Order additional hashes alphabetically when updating pip-compile files

## v0.87.7, 4 January 2019

- Docker: Reduce number of calls to Dockerhub when determining latest version

## v0.87.6, 4 January 2019

- Yarn: de-duplicate indirect dependencies

## v0.87.5, 4 January 2019

- Handle empty versions properly when a build or local version is possible

## v0.87.4, 3 January 2019

- Go (dep): Handle unreachable vanity URLs in parser

## v0.87.3, 3 January 2019

- .NET: Extend timeout for .NET repos
- Maven: More tests for versions that use multiple properties
- Maven: Handle properties with a suffix better

## v0.87.2, 3 January 2019

- Reduce the number of layers in the docker image

## v0.87.1, 2 January 2019

- Register GoModules::Requirement class
- Add go_modules package to Rakefile

## v0.87.0, 2 January 2019

- Go (modules): reorg
- JS: Handle requirements with an || when bumping versions

## v0.86.25, 2 January 2019

- Raise RepoNotFound errors when creating PRs
- Python: Don't treat post-releases as pre-releases

## v0.86.24, 1 January 2019

- Python: Augment hashes from pip-compile if necessary

## v0.86.23, 1 January 2019

- Bump rubygems and bundler versions

## v0.86.22, 1 January 2019

- Revert "Patch Rubygems requirement equality"
- Bump rubygems and bundler versions

## v0.86.21, 1 January 2019

- Ruby: Less strict requirement comparison
- Add TODO to Python pip_compile file updater

## Archived changes between 2017 and 2018

[Changelog archive 2017 to 2018](CHANGELOG_ARCHIVE_2017_TO_2018.md)
