# mobility_active_storage — Design

Translated ActiveStorage attachments for [Mobility](https://github.com/shioyama/mobility).

Implements [shioyama/mobility#633](https://github.com/shioyama/mobility/issues/633), where the
Mobility maintainer declined the feature upstream and suggested a separate gem.

## Goal

```ruby
class Product < ApplicationRecord
  extend Mobility

  translates :title, :description, type: :string   # ordinary Mobility text
  has_one_translated_attached  :document           # this gem
  has_many_translated_attached :photos             # this gem
end

product.document.attach(io: file, filename: "en.pdf", content_type: "application/pdf")
Mobility.with_locale(:fr) { product.document.attach(...) }

product.document           # => Attached::One for the current locale
product.document_fr        # => Attached::One for :fr
product.document?          # => attached? in the current locale
product.document_locales   # => [:en, :fr]
```

## Storage: locale-suffixed attachment names, zero migration

`active_storage_attachments.name` is a plain string column. ActiveStorage attaches no meaning to
it beyond matching the association scope. So a translated `document` is stored as N ordinary
attachments:

| name          | record_type | record_id | blob_id |
| ------------- | ----------- | --------- | ------- |
| `document_en` | Product     | 1         | 10      |
| `document_fr` | Product     | 1         | 11      |

Each is declared with a real `has_one_attached :"document_#{locale}"` in the backend's `setup`
block. That gives us, for free and unmodified: the `document_en_attachment` / `document_en_blob`
associations, the `after_save` / `after_commit` upload hooks, `with_attached_document_en` scopes,
`dependent: :purge_later` on destroy, variants, direct uploads, and per-attachment `service:`.

Rejected alternative: adding a `locale` column to `active_storage_attachments` (the approach
`mobility-actiontext` takes for `action_text_rich_texts`). It requires a migration on a Rails-owned
table, needs the uniqueness index rebuilt, and buys nothing — ActiveStorage, unlike ActionText, has
no uniqueness constraint we need to escape. Encoding the locale in `name` keeps the gem
install-and-go.

Cost of this choice: locales are read from `Mobility.available_locales` when the class body runs,
so adding a locale requires a code reload. Same tradeoff `mobility-actiontext` makes. A `locales:`
option lets callers pin the set explicitly.

## Backend

`Mobility::Backends::ActiveStorage` (registered `:active_storage`) and
`Mobility::Backends::ActiveStorageMany` (registered `:active_storage_many`).

```ruby
def read(locale, **)
  attached(locale)                                  # ActiveStorage::Attached::One
end

def write(locale, value, **)
  name = attachment_name(locale)                    # "document_fr"
  model.attachment_changes[name] =
    if value.nil? || value == ""
      ActiveStorage::Attached::Changes::DeleteOne.new(name, model)
    else
      ActiveStorage::Attached::Changes::CreateOne.new(name, model, value)
    end
end
```

### Why `write` must not call `attach`

This is the one genuinely subtle part of the design, confirmed by spike.

Mobility's `locale_accessors` plugin defines `document_en` / `document_en=` in a module included
*after* ActiveStorage's `GeneratedAssociationMethods`, so **Mobility wins method lookup** — verified:
the owner of `document_en` flips from `Product::GeneratedAssociationMethods` to Mobility's module
once `translates` runs.

`ActiveStorage::Attached::One#attach` is implemented as `record.public_send("#{name}=", attachable)`.
So an `attach` on a translated attribute re-enters *Mobility's* writer, not ActiveStorage's. In the
spike this silently swallowed the attachment — no error, no row written.

Handled by making `write` the single place that mutates `attachment_changes` directly. The two
entry paths then converge correctly rather than fighting:

```
product.document.attach(io)
  → Attached::One#attach
  → record.document_en = io        (intercepted by Mobility's locale accessor)
  → backend.write(:en, io)
  → attachment_changes["document_en"] = CreateOne
  → record.save                    (Attached::One#attach saves)
  → after_save hook from has_one_attached :document_en persists it
```

If `locale_accessors` is disabled, `document_en=` resolves to ActiveStorage's own writer, which sets
the identical `attachment_changes` entry. Both configurations work, which is what makes this safe.

## Fallbacks

Opt-in per attribute; off by default.

```ruby
has_one_translated_attached :document, fallbacks: true          # use Mobility.fallbacks / I18n
has_one_translated_attached :document, fallbacks: { fr: :en }   # explicit
```

Implemented in the backend rather than via Mobility's `fallbacks` plugin. The plugin triggers on a
`nil` read, but `read` must always return an `Attached::One` proxy — returning `nil` for an empty
attachment would break `product.document.attach(...)` on a record that has nothing attached yet.

So: if the current locale has no attachment, walk the fallback chain and return the first locale
that does; if none do, return the current locale's empty proxy, so `.attach` still works. Bypass a
configured fallback with `product.document(fallback: false)`.

**Reads fall back; writes must not.** Returning the fallback locale's proxy directly is wrong —
its `name` is `document_en`, so `product.document.attach(file)` under a `:fr` fallback would
overwrite the English file. (A test caught exactly this.) Instead a read that resolves through a
fallback returns a `FallbackAttached` subclass of Rails' own proxy: `attachment` / `attachments` /
`blobs` resolve through the fallback locale, while `attach`, `purge`, `purge_later` and `detach`
delegate to an ordinary proxy bound to the *current* locale. Subclassing (rather than wrapping in a
delegator) keeps `is_a?(ActiveStorage::Attached::One)` true and lets Rails' own read delegation work
untouched. The subclasses are built lazily, since Active Storage's classes are autoloaded by its
engine, which has not necessarily run when this gem is required from a Gemfile.

Two further Mobility plugins are disabled per attribute, alongside `fallbacks`:

- **`cache`** — it would memoize a proxy resolved through a fallback, so a later attach in the
  current locale would keep returning the fallback locale's file.
- **`dirty`** — compares scalar values, which attachment proxies are not.

These option keys are only passed when the corresponding plugin is actually enabled: Mobility
raises `InvalidOptionKey` for an option belonging to a plugin that is not loaded.

## Generated API

Per attribute `document`, on top of what Mobility's reader/writer/locale_accessors already give:

- `document` / `document=` — current locale
- `document_en`, `document_fr`, … / `document_en=` — explicit locale
- `document?` — `attached?` for the locale (overridden; Mobility's default `present?` is always
  true for a proxy object)
- `document_locales` — locales that actually have an attachment
- `with_attached_document` — scope eager-loading the *current* locale's attachment
- `document_en_attachment`, `document_en_blob`, `with_attached_document_en` — from Rails, untouched

`has_many_translated_attached :photos` mirrors this with `Attached::Many`, `CreateMany` /
`DeleteMany`, and `photos_locales`.

## Macros

`has_one_translated_attached` / `has_many_translated_attached` are defined on `ActiveRecord::Base`
via a Railtie and are thin sugar over `translates`:

```ruby
def has_one_translated_attached(name, fallbacks: false, locales: nil, **as_options)
  extend Mobility unless singleton_class < Mobility
  translates name, backend: :active_storage, fallbacks:, locales:, as_options:
end
```

Auto-extending Mobility means the macro works whether or not the model already calls
`extend Mobility`, and it composes with other `translates` calls on the same model — Mobility
supports multiple `translates` calls with different backends, verified in spike.

Rails' own `has_one_attached` is left alone. Overriding it to accept `translated: true` was
considered and rejected: monkeypatching a core Rails DSL to change its storage semantics is a poor
trade for the few characters saved.

## Out of scope for v1

- **Dirty tracking.** Mobility's `dirty` plugin assumes comparable scalar values. Documented as
  unsupported; ActiveStorage's own `attachment_changes` remains available.
- **Querying.** `Product.i18n.where(document: ...)` is not meaningful for attachments. The backend
  implements `each_locale` so Mobility's Enumerable helpers work, but no Arel integration.

## Testing

Minitest (keeping the scaffolded `rake` default task) against a minimal `Rails::Application` booted
inline in `test/test_helper.rb` — no `test/dummy` app to maintain. In-memory SQLite, ActiveStorage
schema loaded from Rails' own migration templates, `:test` Disk service in a tmpdir torn down after
the run, and `:inline` ActiveJob so purges execute synchronously.

The harness must create **both** `mobility_string_translations` and `mobility_text_translations`
(the spike's only failure was a missing text table surfacing during `destroy`).

Coverage:

1. Attach / read / replace / purge per locale, `has_one` and `has_many`
2. Locale isolation — attaching to `:fr` leaves `:en` untouched
3. Staged attachment on unsaved records, and `create!(document: ...)`
4. `Mobility.with_locale`, locale accessors, `document?`, `document_locales`
5. Fallbacks: off by default, `true`, explicit hash, and `fallback: false` bypass
6. Coexistence with `translates :title, :description` on the same model
7. `destroy` purges every locale's attachment
8. DB-level assertion that `name` values are exactly `document_en` / `document_fr`
