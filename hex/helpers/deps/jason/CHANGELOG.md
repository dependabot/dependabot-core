# Changelog

## 1.1.2 (19.10.2018)

### Bug fixes

* correctly handle the `pretty: false` option
  ([ba318c8](https://github.com/michalmuskala/jason/commit/ba318c8)).

## 1.1.1 (10.07.2018)

### Bug fixes

* correctly handle escape sequences in strings when pretty printing
  ([794bbe4](https://github.com/michalmuskala/jason/commit/794bbe4)).

## 1.1.0 (02.07.2018)

### Enhancements

* pretty-printing support through `Jason.Formatter` and `pretty: true` option
  in `Jason.encode/2` ([d758e36](https://github.com/michalmuskala/jason/commit/d758e36)).

### Bug fixes

* silence variable warnings for fields with underscores used during deriving
  ([88dd85c](https://github.com/michalmuskala/jason/commit/88dd85c)).
* **potential incompatibility** don't raise `Protocol.UndefinedError` in non-bang functions
  ([ad0f57b](https://github.com/michalmuskala/jason/commit/ad0f57b)).

## 1.0.1 (02.07.2018)

### Bug fixes

* fix `Jason.Encode.escape` type ([a57b430](https://github.com/michalmuskala/jason/commit/a57b430))
* multiple documentation improvements

## 1.0.0 (26.01.2018)

No changes

## 1.0.0-rc.3 (26.01.2018)

### Changes

* update `escape` option of `Jason.encode/2` to take values:
  `:json | :unicode_safe | :html_safe | :javascript_safe` for consistency. Old values of
  `:unicode` and `:javascript` are still supported for compatibility with Poison.
  ([f42dcbd](https://github.com/michalmuskala/jason/commit/f42dcbd))

## 1.0.0-rc.2 (07.01.2018)

### Bug fixes

* add type for `strings` option ([b459ee4](https://github.com/michalmuskala/jason/commit/b459ee4))
* support iodata in `decode!` ([a1f3456](https://github.com/michalmuskala/jason/commit/a1f3456))

## 1.0.0-rc.1 (22.12.2017)

Initial release
