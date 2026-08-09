# `attribute_methods: false` is accepted but silently ignored

**Repo:** shioyama/mobility
**Affects:** 1.3.2 (latest release, Jan 2025) and `master` @ `337f32d`
**Tested with:** Ruby 4.0.6, ActiveRecord 8.1.3.1

---

Passing `attribute_methods: false` to `translates` has no effect on the behaviour the plugin is
named for. The attribute is still merged into `attributes`, `translated_attributes` and
`attribute_names_for_serialization`. Only `untranslated_attributes` honours the option.

The option is accepted without warning, so there is no signal that it did nothing.

## Reproduction

Self-contained; no gems beyond `mobility`, `activerecord` and `sqlite3`.

```ruby
require "active_record"
require "mobility"
require "sqlite3"

I18n.available_locales = %i[en fr]
I18n.default_locale = :en
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:posts) { |t| t.string :slug }
  create_table :mobility_string_translations do |t|
    t.string :locale, null: false
    t.string :key, null: false
    t.string :value
    t.integer :translatable_id, null: false
    t.string :translatable_type, null: false
    t.index %i[translatable_id translatable_type locale key], unique: true, name: "i_mst"
  end
end

Mobility.configure do
  plugins do
    backend :key_value
    active_record
    reader
    writer
    attribute_methods
  end
end

class Post < ActiveRecord::Base
  extend Mobility
  translates :title, type: :string, attribute_methods: false
end

post = Post.new(slug: "hello")
post.title = "Hello"

post.attributes.keys                       #=> ["id", "slug", "title"]
post.respond_to?(:translated_attributes)   #=> true
post.translated_attributes                 #=> {"title" => "Hello"}
post.send(:attribute_names_for_serialization)
                                           #=> ["id", "slug", "title"]
post.respond_to?(:untranslated_attributes) #=> false
```

### Expected

`title` absent from `attributes`, `translated_attributes` and `attribute_names_for_serialization` —
i.e. the plugin's documented effect is switched off.

### Actual

All three still include `title`. `untranslated_attributes` is the only thing the option controls,
and it is arguably the least significant of the four.

## Cause

In `lib/mobility/plugins/attribute_methods.rb`, the `initialize_hook` (line 20) never consults the
option:

```ruby
initialize_hook do |*names|
  include InstanceMethods            # defines #attributes => super.merge(translated_attributes)

  define_method :translated_attributes do
    super().merge(names.inject({}) { |a, n| a.merge(n.to_s => send(n)) })
  end

  private

  define_method :attribute_names_for_serialization do
    return unless defined?(super)

    super() + names.map(&:to_s)
  end
end
```

Only the `included_hook` (line 39) reads it:

```ruby
included_hook do
  if options[:attribute_methods]
    define_method :untranslated_attributes, ::ActiveRecord::Base.instance_method(:attributes)
  end
end
```

`Plugin#initialize_hook` (`lib/mobility/plugin.rb:78`) runs its block whenever
`plugin.dependencies_satisfied?` is true, and never looks at the option value — so there is nothing
below to catch the `false`.

### Sibling plugins do guard

This looks like an oversight rather than a deliberate asymmetry — `attribute_methods` is the only
one of these that omits the check:

| Plugin | `initialize_hook` guards on its option? |
| --- | --- |
| `locale_accessors` | yes — `if locales = options[:locale_accessors]` |
| `fallthrough_accessors` | yes — `if options[:fallthrough_accessors]` |
| `dirty` | yes — `if options[:dirty]` |
| `attribute_methods` | **no** |

## Suggested fix

Wrap the `initialize_hook` body in the same guard:

```ruby
initialize_hook do |*names|
  if options[:attribute_methods]
    include InstanceMethods

    define_method :translated_attributes do
      super().merge(names.inject({}) { |a, n| a.merge(n.to_s => send(n)) })
    end

    private

    define_method :attribute_names_for_serialization do
      return unless defined?(super)

      super() + names.map(&:to_s)
    end
  end
end
```

Verified against the reproduction above. With the guard applied:

```
attribute_methods: false
  attributes.keys                   => ["id", "slug"]
  respond_to?(:translated_attributes) => false

default (attribute_methods: true)
  attributes.keys                   => ["id", "slug", "title"]
  translated_attributes             => {"title" => "Hello"}
  untranslated_attributes.keys      => ["id", "slug"]
```

Default behaviour is unchanged, so this should not be a breaking change for anyone who has not
explicitly passed `false`. Happy to open a PR with a test if the approach looks right.

## Why it matters

The plugin's own docs warn that adding translated attributes to `attributes` "can have unexpected
consequences ... may lead to conflicts with other gems" — which is exactly the situation where a
user reaches for `attribute_methods: false`, per-attribute, while keeping the plugin on for the rest
of the app. Today that escape hatch is silently unavailable.

Concretely: I hit this translating Active Storage attachments, where the value merged into
`attributes` is a live `ActiveStorage::Attached` proxy holding a reference back to the record. That
makes `attributes.to_json` and `as_json` raise `SystemStackError`, and
`Model.new(record.attributes)` raise `ArgumentError`. Not something Mobility should have to
accommodate — but with no working opt-out, the only route is to override
`translated_attributes` and `attribute_names_for_serialization` downstream, which is a fragile thing
to rely on.

Possibly related: #563 (`attribute_methods` + `select` raising `MissingAttributeError`) is another
case where the only clean remedy would be turning the plugin off for specific attributes.
