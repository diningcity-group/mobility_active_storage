# mobility_active_storage

Translated [Active Storage](https://guides.rubyonrails.org/active_storage_overview.html)
attachments for [Mobility](https://github.com/shioyama/mobility).

Attach a different file per locale under a single attribute name:

```ruby
class Product < ApplicationRecord
  extend Mobility

  translates :title, :description, type: :string   # ordinary Mobility text
  has_one_translated_attached  :document
  has_many_translated_attached :photos
end
```

```ruby
product.document.attach(io: pdf, filename: "manual.pdf", content_type: "application/pdf")

Mobility.with_locale(:fr) do
  product.document.attach(io: pdf_fr, filename: "manuel.pdf", content_type: "application/pdf")
end

product.document                              # => the :en file
Mobility.with_locale(:fr) { product.document } # => the :fr file
product.document_fr                            # => the :fr file
```

## No migration required

Active Storage's `active_storage_attachments.name` column is a plain string, so each locale is
stored as an ordinary attachment whose name carries the locale:

| name          | record_type | record_id | blob_id |
| ------------- | ----------- | --------- | ------- |
| `document_en` | Product     | 1         | 10      |
| `document_fr` | Product     | 1         | 11      |

Each is declared with a real `has_one_attached` / `has_many_attached` under the hood, so variants,
previews, direct uploads, `purge`, `dependent: :purge_later` on destroy, and the generated
`document_en_attachment` / `document_en_blob` / `with_attached_document_en` all keep working
exactly as Rails defines them.

## Installation

```ruby
# Gemfile
gem "mobility_active_storage"
```

You need Active Storage installed (`bin/rails active_storage:install`) and Mobility configured.
Mobility does not need any translation tables for attachments — if attachments are all you
translate, [installing Mobility without tables](https://github.com/shioyama/mobility#activerecord-rails)
is enough.

`extend Mobility` is optional: the macros extend the model for you if it isn't already.

## Usage

### Reading and writing

Everything Active Storage's own proxy supports works, scoped to the current locale:

```ruby
product.document.attach(uploaded_file)
product.document.attached?      # => true
product.document.filename       # => "manual.pdf"
product.document.purge          # purges only the current locale's file
product.document = nil          # detaches only the current locale's file

product.photos.attach(one, two) # appends, per locale
product.photos = [one]          # replaces the current locale's collection
```

Assignment works on unsaved records and in `create`, so form params flow through normally:

```ruby
Product.create!(title: "Widget", document: params[:document])
```

### Generated methods

For `has_one_translated_attached :document`:

| Method                        | Description                                              |
| ----------------------------- | -------------------------------------------------------- |
| `document`                    | `ActiveStorage::Attached::One` for the current locale     |
| `document=`                   | Attach/detach in the current locale                       |
| `document_en`, `document_fr`  | A specific locale (dashed locales normalize: `pt_br`)     |
| `document?`                   | Whether a file is attached in the current locale          |
| `document_locales`            | Locales that actually have an attachment, e.g. `[:en, :fr]` |
| `Product.with_attached_document` | Eager-loads whichever locale is current                 |

`has_many_translated_attached :photos` mirrors these with `ActiveStorage::Attached::Many`.

`document_locales` costs one query however many locales the attribute declares, and counts pending
changes the way `attached?` does: a staged attach is included before it is saved, a staged purge
excluded straight away. It does not memoize, so hold the result if you need it more than once.

### Fallbacks

Off by default. Enable per attribute:

```ruby
has_one_translated_attached :document, fallbacks: true          # I18n's chain, ending at the default locale
has_one_translated_attached :document, fallbacks: { fr: :en }   # explicit
```

Reads then resolve through the chain, while **writes always stay in the current locale** — so
attaching, purging or detaching under a fallback never touches the file you fell back to:

```ruby
product.document.attach(en_file)               # :en has a file, :fr does not

Mobility.with_locale(:fr) do
  product.document.filename                    # => the :en file
  product.document(fallback: false).attached?  # => false
  product.document.attach(fr_file)             # creates document_fr; document_en untouched
end
```

Pass `fallback: :ja` or `fallback: [:ja, :en]` to override the chain for a single read. That
override only applies where fallbacks are configured — an attribute declaring no fallbacks cannot be
talked into one by a read option, so `fallbacks: false` is enforceable even if a caller forwards
untrusted options into the reader. This matches Mobility, whose fallbacks plugin is inert when
`fallbacks: false`.

### Options

Both macros accept:

- `fallbacks:` — `true`, or a hash such as `{ fr: :en }`. Default `false`.
- `locales:` — which locales to declare attachments for. Defaults to `Mobility.available_locales`.
- any remaining options are forwarded to Rails, e.g. `service:`, `strict_loading:`, `dependent:`.

```ruby
has_one_translated_attached :document, locales: %i[en fr], service: :s3, strict_loading: true
```

### Using the backend directly

The macros are sugar over ordinary Mobility backends, which you can also use directly:

```ruby
translates :document, backend: :active_storage
translates :photos,   backend: :active_storage_many
```

The macros additionally switch off the Mobility plugins that assume a scalar value. Declaring the
backend directly means doing that yourself, for whichever of them you have enabled:

```ruby
translates :document, backend: :active_storage, fallbacks: false, cache: false, dirty: false
```

Passing an option for a plugin you have *not* enabled raises `Mobility::Pluggable::InvalidOptionKey`,
so pass only the ones that apply. Keeping attachments out of `attributes` is handled by the backend
itself, so it applies on this path too.

## Strong parameters

Each locale gets its own set of writers. `has_one_translated_attached :document` on a four-locale
app defines `document=`, `document_en=`, `document_fr=`, `document_ja=`, `document_pt_br=` (plus the
`_attachment=` / `_blob=` association writers Rails generates), and they all work through mass
assignment. That is inherent to `has_one_attached`, but the names are not obvious from the single
macro call in your model.

Permit only the bare attribute name, which routes through Mobility to the current locale:

```ruby
params.expect(product: [:title, :document, photos: []])
```

Permit the `_<locale>` variants only where a locale switcher genuinely needs them. A blanket
`permit!`, or a filter matching `/\Adocument/`, would let a user overwrite a locale they were never
editing — and with fallbacks enabled, that changes what other locales serve too.

## Rails compatibility

Requires **Rails >= 7.0.8** and Ruby >= 3.2. Tested in CI against Rails 7.0.8, 7.2, 8.0 and
latest, on Ruby 3.2 through 4.0.

The floor is a patch release because this gem depends directly on Active Storage's attachment
behaviour, and the 7.0 line needs to stay at or above the patched 7.0.8 release. If you need an
older 7.0.x build, this project does not support it.

Run [bundler-audit](https://github.com/rubysec/bundler-audit) or Dependabot in your application to
stay ahead of new advisories.

## Notes and limitations

**Locales are read when the class body runs.** Attachments are declared for
`Mobility.available_locales` at that moment, so adding a locale needs a code reload. Pass
`locales:` to pin the set explicitly.

**Mobility's `fallbacks` plugin is disabled for these attributes**, and this gem implements
fallbacks itself. Mobility's plugin triggers on a `nil` read, but an attachment reader has to
return a proxy even when nothing is attached, or `product.document.attach(...)` would fail on a
record with no file yet.

**The `cache` plugin is disabled** for these attributes, since it would memoize a proxy resolved
through a fallback and keep returning the fallback locale's file after a later attach.

**Dirty tracking is not supported.** Mobility's `dirty` plugin compares scalar values; it is
disabled for these attributes. Active Storage's own `attachment_changes` still works.

**Attachment attributes are kept out of `attributes`.** Mobility's `attribute_methods` plugin
merges every translated attribute into `attributes`, `translated_attributes` and
`attribute_names_for_serialization`. For an attachment that value would be a live
`ActiveStorage::Attached` proxy holding a reference back to the record, which makes the hash
unserialisable (`attributes.to_json` and `as_json` recurse until the stack overflows) and unusable
for mass assignment (`Model.new(record.attributes)` raises `ArgumentError`, since Active Storage
rejects a proxy as an attachable). Rails' own `has_one_attached` puts nothing in `attributes`, and
neither does this gem — a proxy is not a serialisable value. Translated *text* attributes are
unaffected and still appear as Mobility intends.

Note that `attribute_methods: false` is not a workaround: Mobility 1.3.2 accepts the option and
silently ignores it, because the plugin's `initialize_hook` is gated on `dependencies_satisfied?`
rather than on the option value.

**Querying is not supported.** `Product.i18n.where(document: ...)` is not meaningful for
attachments — there is no comparable column, only rows in `active_storage_attachments`. The
backend raises `MobilityActiveStorage::Error` explaining this rather than failing obscurely inside
Arel. Query the attachments directly, filtering on `name` (for example `"document_en"`).

## Development

```sh
bin/setup
bundle exec rake        # tests + rubocop

# against a specific Rails version
BUNDLE_GEMFILE=gemfiles/rails_7.0.8.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.0.8.gemfile bundle exec rake test
```

The suite boots a minimal `Rails::Application` in `test/test_helper.rb` against in-memory SQLite,
so there is no dummy app to maintain.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/barnaclebarnes/mobility_active_storage.

## License

Available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
