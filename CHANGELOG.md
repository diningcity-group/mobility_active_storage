# Changelog

## [Unreleased]

Pre-release fixes from a security review of the initial commit.

- A `fallback:` read option is now honoured only where the attribute actually configures
  fallbacks. Previously `document(fallback: :ja)` cross-read another locale even on an attribute
  declaring `fallbacks: false`, so the declaration was not enforceable by a caller forwarding
  untrusted options. Matches Mobility, whose fallbacks plugin is inert when `fallbacks: false`.
- `with_attached_*` scopes now validate the current locale against the attribute's configured
  locales, raising the same `MobilityActiveStorage::Error` as the read path instead of an
  `ActiveRecord::AssociationNotFoundError` about a generated association name.
- The lazily built fallback proxy classes are now guarded by a mutex.
- Raised the `activerecord` / `activestorage` floor to `>= 7.2.3.2`, the earliest release clearing
  every current Active Storage advisory. Rails 7.0 and 7.1 are end-of-life with no fix available for
  those advisories, and this gem serves more attachments through exactly the affected paths.
- CI runs a Rails 7.2/8.0/latest matrix on Ruby 3.2-3.4, plus `bundler-audit`. Actions are pinned
  by SHA.
- README: strong-parameters guidance for the per-locale writers, and Rails version security notes.

## [0.1.0] - 2026-08-07

- Initial release.
- `has_one_translated_attached` and `has_many_translated_attached` macros on Active Record models.
- `Mobility::Backends` registrations for `:active_storage` and `:active_storage_many`.
- Per-locale attachments stored under locale-suffixed Active Storage attachment names
  (`document_en`, `document_fr`), requiring no migration.
- Opt-in per-attribute fallbacks, where reads resolve through the fallback chain while writes
  stay in the current locale.
- `#{attribute}_locales` and a current-locale `with_attached_#{attribute}` scope.
