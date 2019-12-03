2.12.2
----

* FIX: return tags/extra for [@rivayama, #931]

2.12.1
----

* FIX: undefined method `[]' for nil:NilClass [@HazAT, #932]

2.12.0
----

* FIX: Remove duplicate message when exception is emitted
* FIX: Frozen string bug in utf8conversation
* FEATURE: Allow block on tags_context and extra_context

2.11.3
----

* FIX: infinite backoff under pressure [@Bonias, #886]

2.11.2
----

* REF: Warn on 4xx error [@iloveitaly, #862]

2.11.1
----

* FIX: Call `to_s` on breadcrumb message [@halkeye, #914]

2.11.0
----

* FEATURE: Prepend the transaction around_action so libraries with controllers can alter the value. [@drcapulet, #887]

2.10.0
-----

* FEATURE: Added support for `SENTRY_ENVIRONMENT` [@mtsmfm, #910]
* FEATURE: Added support for `SENTRY_RELEASE` [@coorasse, #911]

2.9.0
-----

* FEATURE: Added `config.inspect_exception_causes_for_exclusion`. Determines if the exception cause should be inspected for `config.excluded_exceptions` option. [@effron, #872]


2.8.0
-----

* FEATURE: Added `config.before_send`. Provide a lambda or proc to this config setting, which will be `call`ed before sending an event to Sentry. Receives `event` and `hint` as parameters. `hint` is a hash `{:exception => ex | nil, :message => message | nil}`. [@hazat, #882]

2.7.4
-----

* BUGFIX: Correctly handle public only DSNs [@mitsuhiko, #847]
* BUGFIX: context attributes with nil raised error [@joker-777, 824]
* BUGFIX: Suppress warning about enabling dyno metadata in Heroku CI [@meganemura, #833]

2.7.3
-----

* BUGFIX: Fix proxy settings for Faraday [@Strnadj, #820]
* BUGFIX: Fix duplicated events in ActiveJob w/DelayedJob and Sidekiq [@BrentWheeldon, #815]

2.7.2
-----

* BUGFIX: GlobalIDs are now displayed correctly in Sidekiq contexts [@louim, #798]
* BUGFIX: If git is not installed, fail silently during release detection [@nateberkopec]
* BUGFIX: We do not support rack-timeout <= 0.2, fix errors when incompat version present [@nateberkopec]
* BUGFIX: Put cookies in the correct spot of event [@nateberkopec, #812]
* BUGFIX: Exception context is deep_merged [@janklimo, #782]

2.7.1
-----

* BUGFIX: Fixed LocalJumpError in Rails controllers [@nateberkopec w/@frodsan, #774]

2.7.0
-----

* FEATURE: Add random sampling. [@nateberkopec, #734]
* FEATURE: Transactions. See Context docs for usage. [@nateberkopec, #743]
* FEATURE: You can set the current environment for Sentry via `SENTRY_CURRENT_ENV` env variable. Useful if your staging environment's RACK_ENV is "production", for example. [@tijmenb, #736]

* BUGFIX: Fix wrapped classnames in old versions of Sidekiq and ActiveJob [@nateberkopec, #702]
* BUGFIX: Server names on Heroku were pretty useless before - now they follow the dyno name ("worker.1", "web.2") [@nateberkopec, #703]
* BUGFIX: ActiveJob::DeserializationError is now ignored by default. Not doing so can cause infinite loops if you are using an ActiveJob async callback. [@nateberkopec, #701]
* BUGFIX: Binary conversion to UTF-8 when binary is frozen is fixed [@nateberkopec, #757]
* BUGFIX: Our credit-card regex now matches Sentry's server behavior, which means it does not censor milliseconds since the epoch [@nateberkopec, #771]

* REFACTOR: We now use an updated port of Rails' deep_merge which should be 5-10% faster [@nateberkopec, #770]
* REFACTOR: Tests have been cleaned up, and now run in random order. [@nateberkopec]
* REFACTOR: Raven::Event has been refactored a bit [@nateberkopec]

2.6.3
-----

* BUGFIX: Fixed typo in the Heroku warning [@greysteil, #728]
* BUGFIX: Swallow IOErrors when reading the Rack request body [@nateberkopec]
* BUGFIX: Fix invalid UTF-8/circular references when using async [@nateberkopec, #730]

2.6.2
-----

* BUGFIX: If using the Sidekiq or DelayedJob adapters with ActiveJob, ActiveJob wouldn't re-raise upon capturing an exception. [@nateberkopec, 5b02ad4ff2]

* KNOWN ISSUE: When using `async`, Rack integration is not thread-safe [#721]
* KNOWN ISSUE: When using `async`, encoding errors may be raised [#725]

2.6.1
-----

* BUGFIX: Fix cases where ActionDispatch::RemoteIP would blow up during event creation [@cmoylan, #722]
* BUGFIX: In ActiveJob, don't report exceptions which can be rescued by rescue_from handlers [@bensheldon, #719]

2.6.0
-----

* FEATURE: raven-ruby now marks itself as the "ruby" logger by default, to match raven-js behavior [@nateberkopec]
* FEATURE: You may now override the default sanitization parameters [#712, @nateberkopec]
* FEATURE: Breadcrumb buffers are now publicly accessible [#686, @nateberkopec]
* FEATURE: We yell at you now if you're using Heroku but don't have runtime-dyno-metadata enabled [#715, @nateberkopec]
* FEATURE: project_root will always be set, regardless of framework [#716, @nateberkopec]

* BUGFIX: Request body and message limits now match Sentry server defaults [#714, @nateberkopec]
* BUGFIX: Sidekiq context now works as expected [#713, @nateberkopec]
* BUGFIX: Capture exceptions in ActiveJob when not using Sidekiq adapter [#709, #671, @nateberkopec]

2.5.3
-----

* BUGFIX: Deal properly with ASCII_8BIT/BINARY encodings [#689, #696, @nateberkopec]

2.5.2
-----

* BUGFIX: raven test executable should be available [#691, @nateberkopec]
* BUGFIX: Fix stack overflow when calling Backtrace#inspect [#690, @nateberkopec]

* KNOWN ISSUE: Character encoding errors [#689]

2.5.1
-----

* BUGFIX: Fix case where Pathname objects are on the load path [@nateberkopec]
* BUGFIX: Fix bad UTF-8 characters in the URL querystring [@nateberkopec]
* BUGFIX: Fix case where rack-timeout could be required twice [@nateberkopec]

* REFACTOR: Slightly cleaner character encoding fixing [@nateberkopec, @bf4]

2.5.0
-----

* FEATURE: Greatly improved performance (2-3x faster capture) [@nateberkopec]
* FEATURE: Frozen objects are now sanitized [@nateberkopec]

* BUGFIX: Grabbing Sidekiq context from "wrapped" classes works [@nateberkopec]
* BUGFIX: Relaxed Faraday dependency [@nateberkopec]

2.4.0
-----

* FEATURE: Allow customization of the Faraday adapter [#639, @StupidCodeFactory]

* BUGFIX: Report the SDK name as "raven-ruby", not "sentry-raven" [#641, @bretthoerner]
* BUGFIX: Sidekiq jobs now clear context/breadcrumbs properly between jobs [#637, @drewish]
* BUGFIX: Overriding the logger in Rails wasn't working [#638, @eugeneius]

2.3.1
-----

* BUGFIX: Backtrace parser fixed for JRuby 9k [#619, @the-michael-toy]
* BUGFIX: Rake tasks should show the correct task name [#621, @Bugagazavr]
* BUGFIX: Formatted messages work if params are `nil` [#625, @miyachik]
* BUGFIX: Backtrace logger on failed event send works with custom formatters [#627, @chulkilee]
* BUGFIX: Fix typo that caused Version headers to not be corrected [#628, @nateberkopec]
* BUGFIX: Faraday errors are more descriptive when no server response [#629, @drewish]
* BUGFIX: DelayedJob handler no longer truncates unneccessarily short [#633, @darrennix]
* BUGFIX: Fix several processors not working correctly w/async jobs stored in backends like Redis [#634, @nateberkopec]

2.3.0
-----

* CHANGE: Log levels of some messages have been changed. Raven logger is INFO level by default. [@nateberkopec]
* BUGFIX: Exception messages are now limited to 10,000 bytes. [#617, @mattrobenolt]

2.2.0
-----

* ENHANCEMENT: Sentry server errors now return some information about the response headers. [#585, @rafadc]
* BUGFIX/ENHANCEMENT: Frozen objects are no longer sanitized. This prevents some bugs, but you can now also freeze objects if you don't want them to be sanitized by the SanitizeData processor. [#594, @nateberkopec]
* ENHANCEMENT: The ability to use Raven::Instance alone is greatly improved. You can now call #capture_exception directly on an Instance (#595), give it it's own Logger (#599), and set it's own config which will be used when creating Events (#601). Thanks to
* ENHANCEMENT: You may now provide your own LineCache-like class to Raven. This is useful if you have source code which is not available on disk. [#606, @nateberkopec]
* BUGFIX: Raven no longer emits anything to STDOUT if a system command fails [#596, @nateberkopec]
* ENHANCEMENT: Raven now tells you exactly why it will not send an event in the logs [#602, @nateberkopec]

2.1.4
-----

* FIX: Remove `contexts` key, because it was disabling browser auto-tagging [#587, @nateberkopec]

2.1.3
-----

* Move `os` context key to `server_os` [@nateberkopec]

2.1.2
-----

* FIX: `sys_command` not falling back to Windows commands properly, logging output [@jmalves, @nateberkopec]

2.1.1
-----

* FIX: Message params should accept nil [@jmalves, #570]

2.1.0
-----

ENHANCEMENTS:

* Your client version is now included in all Events. [@nateberkopec, #559]
* OS and Ruby runtime information now included in all Events. [@nateberkopec, #560]
* Transport errors (like Sentry 4XX errors) now raise Sentry::Error, not Faraday errors. [@nateberkopec, #565]
* Sidekiq integration is streamlined and improved. Supports Sidekiq 3.x and up. [@nateberkopec, #555]

FIXES:

* Heroku release detection is improved and more accurate. You must `heroku labs:enable runtime-dyno-metadata` for it to work. [@nateberkopec, #566]

2.0.2
-----

* FIX: Don't set up Rack-Timeout middleware. [@janraasch, #558]

2.0.1
-----

* FIX: UUIDs were being rejected by Sentry as being too long [@nateberkopec]

2.0.0
-----

BREAKING CHANGES:

* The object passed to the `async` callback is now a JSON-compatible hash, not a Raven::Event. This fixes many bugs with backend job processors like DelayedJob. [@nateberkopec, #547]
* Several deprecated accessors have been removed [@nateberkopec, #543]
* You can no longer pass an object which cannot be called to `should_capture` [@nateberkopec, #542]

ENHANCEMENTS:

* Rack::Timeout exceptions are now fingerprinted by URL, making them more useful [@nateberkopec, #538]
* Added an HTTP header processor by default. We now scrub `Authorization` headers correctly. You can use `config.sanitize_http_headers` to add a list of HTTP headers you don't want sent to Sentry (e.g. ["Via", "Referer", "User-Agent", "Server", "From"]) [@nateberkopec]

FIXES:

* User/Event IP addresses are now set more accurately. This will fix many issues with local proxy setups (nginx, etc). [@nateberkopec, #546]
* We now generate a real UUID in the correct format for Event IDs [@nateberkopec, #549]
* If `async` sending fails, we retry with sync sending. [@nateberkopec, #548]
* Changed truncation approach - event messages and HTTP bodies now limited to the same amount of characters they're limited to at the Sentry server [@nateberkopec, #536]

OTHER:

* Codebase cleaned up with Rubocop [@nateberkopec, #544]

1.2.3
-----

* ENHANCEMENT: Send the current environment to Sentry [@dcramer, #530]
* BUGFIX: Fix all warnings emitted by Ruby verbose mode [@nateberkopec]
* BUGFIX: Fix compat with `log4r` [@nateberkopec, #535]

1.2.2
-----

* BUGFIX: NameError in DelayedJob integration. [janraasch, #525]

1.2.1
-----

* BUGFIX: Context clearing should now work properly in DelayedJob and Sidekiq. Also, we properly clear context if Sentry causes an exception. [nateberkopec, #520]
* BUGFIX: If Sentry will not send the event (due to environments or no DSN set), it will not attempt to "capture" (construct an event) [nateberkopec, #518]

1.2.0
-----

* FEATURE: Raven now supports Breadcrumbs, though they aren't on by default. Check the docs for how to enable. [dcramer, #497]
* FEATURE: Raven is no longer a singleton, you may have many `Raven::Instance`s. [phillbaker, #504]
* PERFORMANCE: Raven no longer uses a vendored JSON implementation. JSON processing and encoding should be up to 6x faster. [dcramer, #510]
* BUGFIX: silence_ready now works for Rails apps. [ream88, #512]
* BUGFIX: transport_failure_callback now works correctly [nateberkopec, #508]

1.1.0
-----

* The client exposes a ``last_event_id`` accessor at `Raven.last_event_id`. [dcramer, #493]
* PERFORMANCE: Skip identical backtraces from "re-raised" exceptions [databus23, #499]
* Support for ActionController::Live and Rails template streaming [nateberkopec, #486]

1.0.0
-----

We (i.e. @nateberkopec) decided that `raven-ruby` has been stable enough for some time that it's time for a 1.0.0 release!

BREAKING CHANGES:

- Dropped support for Ruby 1.8.7 [nateberkopec, #465]
- `raven-ruby` no longer reports form POST data or web cookies by default. To re-enable this behavior, remove the appropriate Processors from your config (see docs or PR) [nateberkopec, #466]
- UDP transport has been removed [dcramer, #472]

OTHER CHANGES:

- Improved performance [zanker]
- Deprecated `config.catch_debugged_exceptions`, replaced with `config.rails_report_rescued_exceptions`. `catch_debugged_exceptions` will be removed in 1.1. [nateberkopec, #483]
- Added `config.transport_failure_callback`. Provide a lambda or proc to this config setting, which will be `call`ed when Sentry returns a 4xx/5xx response. [nateberkopec, #484]
- JRuby builds fixed [RobinDaugherty]
- Fix problems with duplicate exceptions and `Exception.cause` [dcramer, #490]
- Added Exception Context. Any Exception class can define a `raven_context` instance variable, which will be merged into any Event's context which contains this exception. [nateberkopec, #491]
+ Documentation from shaneog, squirly, dcramer, ehfeng, nateberkopec.

0.15.6
------

- Fixed bug where return value of debug middleware was nil [eugeneius, #461]
- Fixed a bug in checking `catch_debugged_exceptions` [greysteil, #458]
- Fixed a deprecation warning for Rails 5 [Elektron1c97, #457]

0.15.5
------

- DelayedJob integration fixed when last_error not present [dcramer, #454]
- Release detection doesn't overwrite manual release setting in Rails [eugeneius, #450]
- Deal properly with Cap 3.0/3.1 revision logs [timcheadle, #449]
- Rails 5 support [nateberkopec, #423]

0.15.4
------

- DelayedJob integration now also truncates last_error to 100 characters [nateberkopec]
- Fix several issues with release detection - silence git log message, fix Capistrano detection [nateberkopec, kkumler]


0.15.3
------

- Double exception reporting in Rails FIXED! [nateberkopec, #422]
- Rails 3 users having issues with undefined runner fixed [nateberkopec, #428]
- Sidekiq integration works properly when ActiveJob enabled [mattrobenolt]
- Fix problems with invalid UTF-8 in exception messages [nateberkopec, #426]
- Backtraces now consider "exe" directories part of the app [nateberkopec, #420]
- Sinatra::NotFound now ignored by default [drcapulet, #383]
- Release versions now properly set. Support for Heroku, Capistrano, and Git. [iloveitaly #377, Sija #380]
- DelayedJob integration plays well with ActiveJob [kkumler, #378]
- DelayedJob handlers now truncated [nateberkopec, #431]
- Tons of code quality improvements [amatsuda, ddrmanxbxfr, pmbrent, cpizzaia, wdhorton, PepperTeasdale]

0.15.2
------

- Reverted ActiveJob support due to conflicts [#368]

0.15.1
------

- Fix ActiveJob support [greysteil, #367]

0.15.0
------

- Remove Certifi and use default Ruby SSL config [zanker, #352]
- Support for ``fingerprint`` [dcramer]
- Improved documentation and tests around various attributes [dcramer]
- Allow configurable integrations [cthornton]
- Prevent recursion with ``Exception.cause`` [dcramer, #357]
- Use empty hash if false-y value [GeekOnCoffee, #354]
- Correct some behavior with at_exit error capturing [kratob, #355]
- Sanitize matches whole words [alyssa, #361]
- Expose more debugging info to active_job integration [tonywok, #365]
- Capture exceptions swallowed by rails [robertclancy, #343]
- Sanitize the query string when the key is a symbol [jason-o-matic, #349]
- Moved documentation to docs.getsentry.com [mitsuhiko]

0.14.0
------

- Correct handling of JRuby stacktraces [dcramer]
- Better handling of unreachable file contexts [dcramer, #335]
- SSL is now default ON [dcramer, #338]
- Capture exceptions in runner tasks [eugeneius, #339]
- ActiveJob integration [lucasmazza, #327]
- Cleanup return values of async blocks [lucasmazza, #344]
- Better handling when sending NaN/Infinity JSON values [Alric, #345]
- Fix issues with digest/md5 namespace [lsb, #346]

0.13.3
------

- Fix a deprecation warning being shown in regular operation [ripta, #332]

0.13.2
------

- DelayedJob integration now includes the job id [javawizard, #321]
- Rails integration now works properly when you're not using all parts of Rails (e.g. just ActiveRecord) [lucasmazza, #323]
- Bugfix CLI tool when async config is on [if1live, #324]
- Fix and standardize tag hierarchies. Event tags > context tags > configuration tags in all cases. [JonathanBatten, #322 and eugeneius, #330]
- Using #send on Client, Base, and Transports is now deprecated. See [the commit](https://github.com/getsentry/raven-ruby/commit/9f482022a648ab662c22177ba24fd2e2b6794c34) (or the deprecation message) for their replacements. [nateberkopec, #326]
- You can now disable credit-card-like value filtering. [codekitchen, #329]

0.13.1
------

- Raven::Transports::HTTP#send returns the response now. [eagletmt, #317]
- Filenames now work a lot better when you vendor your gems. [eugeneius, #316]
- Fix raven:test issue when testing non-async configurations. [weynsee, #318]
- Fix blockless Raven#capture. [dinosaurjr, #320]
- Fix some log messages [eagletmt, #319]

0.13.0
------

- Support exception chaining [javawizard, #312]
- Add support for sending release version [eugeneius, #310]
- Better status reports on configuration [faber, #309]
- Client "send" method accepts an event in object or hash format - this will make it much easier to send Sentry events in a delayed job! [marclennox, #300]
- Fix duplicate fields in SanitizeData [wyattisimo, #294]
- Always preserve filename paths under project_root [eugeneius, #291]
- Truncate project root prefixes from filenames [eagletmt, #278]
- Renamed should_send callback to should_capture [nateberkopec, #270]
- Silencing the ready message now happens in the config as normal [nateberkopec, #260]
- Various internal refactorings [see here](https://github.com/getsentry/raven-ruby/compare/0-12-stable...master)

0.12.3
------

- URL query parameters are now sanitized for sensitive data [pcorliss, #275]
- Raven::Client can now use a proxy server when sending events to Sentry [dcramer, #277]
- Raven::Client will now use a timed backoff strategy if the server fails [codekitchen, #267]
- Automatic integration loading is now a lot less brittle [dcramer, handlers, #263, #264]
- Fixed some issues with prefixes and DSN strings [nateberkopec, #259]
- If Raven is initialized without a server config, it will no longer send events [nateberkopec, #258]
- Slightly nicer credit-card-like number scrubbing [nateberkopec, #254]
- Fix some exceptions not being caught by Sidekiq middleware [nateberkopec, #251]
- Uncommon types are now encoded correctly [nateberkopec, #249]

0.12.2
------

- Security fix where exponential numbers in specially crafted params could cause a CPU attack [dcramer, #262]

0.12.1
------

- Integrations (Sidekiq, DelayedJob, etc) now load independently of your Gemfile order. [nateberkopec, #236]
- Fixed bug where setting tags mutated your configuration [berg, #239]
- Fixed several issues with SanitizeData and UTF8 sanitization processors [nateberkopec, #238, #241, #244]

0.12.0
------

- You can now give additional fields to the SanitizeData processor. Values matched are replaced by the string mask (*********). Full documentation (and how to use with Rails config.filter_parameters) [here](https://docs.getsentry.com/hosted/clients/ruby/config/). [jamescway, #232]
- An additional processor has been added, though it isn't turned on by default: RemoveStacktrace. Use it to remove stacktraces from exception reports. [nateberkopec, #233]
- Dependency on `uuidtools` has been removed. [nateberkopec, #231]

0.11.2
------

- Fix some issues with the SanitizeData processor when processing strings that look like JSON


0.11.1
------

- Raven now captures exceptions in Rake tasks automatically. [nateberkopec, troelskn #222]
- There is now a configuration option called ```should_send``` that can be configured to use a Proc to determine whether or not an event should be sent to Sentry. This can be used to implement rate limiters, etc. [nateberkopec, #221]
- Raven now includes three event processors by default instead of one, which can be turned on and off independently. [nateberkopec, #223]
- Fixed bug with YAJL compatibility. [nateberkopec, #223]

0.10.1
------

- Updated to RSpec 3.
- Apply filters to encoded JSON data.


0.10.0
------

- Events are now sent to Sentry in all environments. To change this behavior, either unset ```SENTRY_DSN``` or explicitly configure it via ```Raven.configure```.
- gzip is now the default encoding
- Removed hashie dependency


0.9.0
-----

- Native support for Delayed::Job [pkuczynski, #176]
- Updated to Sentry protocol version 5


0.5.0
-----
- Rails 2 support [sluukonen, #45]
- Controller methods in Rails [jfirebaugh]
- Runs by default in any environment other than test, cucumber, or development. [#81]
