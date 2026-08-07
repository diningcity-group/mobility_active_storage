# Changelog

## [Unreleased]

## [0.1.0] - 2026-08-07

- Initial release.
- `has_one_translated_attached` and `has_many_translated_attached` macros on Active Record models.
- `Mobility::Backends` registrations for `:active_storage` and `:active_storage_many`.
- Per-locale attachments stored under locale-suffixed Active Storage attachment names
  (`document_en`, `document_fr`), requiring no migration.
- Opt-in per-attribute fallbacks, where reads resolve through the fallback chain while writes
  stay in the current locale.
- `#{attribute}_locales` and a current-locale `with_attached_#{attribute}` scope.
