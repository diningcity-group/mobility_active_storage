# Minimal reproduction: Mobility only. No ActiveStorage, no third-party gems.
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
    t.index %i[translatable_id translatable_type locale key], unique: true, name: "i_msT"
  end
end

Mobility.configure do
  plugins do
    backend :key_value
    active_record
    reader
    writer
    attribute_methods      # the plugin under test
  end
end

class Post < ActiveRecord::Base
  extend Mobility
  translates :title, type: :string, attribute_methods: false
end

post = Post.new(slug: "hello")
post.title = "Hello"

puts "mobility #{Mobility::VERSION::STRING}, activerecord #{ActiveRecord::VERSION::STRING}"
puts
puts "translates :title, attribute_methods: false"
puts
puts "  attributes.keys                      => #{post.attributes.keys.inspect}"
puts "  respond_to?(:translated_attributes)  => #{post.respond_to?(:translated_attributes)}"
puts "  translated_attributes                => #{post.translated_attributes.inspect}"
puts "  attribute_names_for_serialization    => #{post.send(:attribute_names_for_serialization).inspect}"
puts "  respond_to?(:untranslated_attributes)=> #{post.respond_to?(:untranslated_attributes)}"
puts
puts "expected: 'title' absent from all three; untranslated_attributes undefined"
puts "actual:   only untranslated_attributes honoured the option"
