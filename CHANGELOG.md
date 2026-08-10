# Changelog

## Unreleased

- `#{attribute}_locales` now answers in one query instead of one per configured locale. It probed
  each locale's attachment proxy in turn, so a model declared for 73 locales issued 73 statements
  every time it was asked -- and any caller that reads it per row (a serializer, a validation) paid
  that per row. Pending attachment changes still take precedence over the stored rows, so a staged
  attach counts before it is saved and a staged purge stops counting straight away.

## [0.1.1] - 2026-08-10

- No user-facing changes. Released to verify the trusted-publishing workflow; the packaged files
  are identical to 0.1.0.

## [0.1.0] - 2026-08-10

- Initial release.
- `has_one_translated_attached` and `has_many_translated_attached` macros on Active Record models.
- `Mobility::Backends` registrations for `:active_storage` and `:active_storage_many`.
- Per-locale attachments stored under locale-suffixed Active Storage attachment names
  (`document_en`, `document_fr`), requiring no migration.
- Opt-in per-attribute fallbacks, where reads resolve through the fallback chain while writes
  stay in the current locale.
- `#{attribute}_locales` and a current-locale `with_attached_#{attribute}` scope.

Fixes from a security review of the initial commit, all included in this release:

- A `fallback:` read option is now honoured only where the attribute actually configures
  fallbacks. Previously `document(fallback: :ja)` cross-read another locale even on an attribute
  declaring `fallbacks: false`, so the declaration was not enforceable by a caller forwarding
  untrusted options. Matches Mobility, whose fallbacks plugin is inert when `fallbacks: false`.
- `with_attached_*` scopes now validate the current locale against the attribute's configured
  locales, raising the same `MobilityActiveStorage::Error` as the read path instead of an
  `ActiveRecord::AssociationNotFoundError` about a generated association name.
- The lazily built fallback proxy classes are now guarded by a mutex.
- Translated attachments are no longer merged into `attributes`, `translated_attributes` or
  `attribute_names_for_serialization` by Mobility's `attribute_methods` plugin. The value there
  was a live `ActiveStorage::Attached` proxy referencing the record, so `attributes.to_json` and
  `as_json` raised `SystemStackError` and `Model.new(record.attributes)` raised `ArgumentError`.
  Rails' own `has_one_attached` puts nothing in `attributes`; this now matches. (`attribute_methods:
  false` is not a workaround -- Mobility 1.3.2 accepts and silently ignores it.)
- Querying a translated attachment now raises `MobilityActiveStorage::Error` with an explanation
  instead of a `NoMethodError` from inside Mobility's query plugin.
- The test harness now enables `attribute_methods`, `query`, `dirty` and `fallthrough_accessors`,
  which it previously did not, so the suite exercises a maximal Mobility configuration.
- Raised the `activerecord` / `activestorage` floor to `>= 7.2.3.2`, the earliest release clearing
  every current Active Storage advisory. Rails 7.0 and 7.1 are end-of-life with no fix available for
  those advisories, and this gem serves more attachments through exactly the affected paths.
- CI runs a Rails 7.2/8.0/latest matrix on Ruby 3.2 through 4.0, plus `bundler-audit`. Actions are
  pinned by SHA.
- README: strong-parameters guidance for the per-locale writers, and Rails version security notes.
