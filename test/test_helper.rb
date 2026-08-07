# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV["RAILS_ENV"] = "test"

require "logger"
require "tmpdir"
require "stringio"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "sqlite3"

require "mobility"

STORAGE_ROOT = Dir.mktmpdir("mobility-active-storage-test")
Minitest.after_run { FileUtils.remove_entry(STORAGE_ROOT) if File.directory?(STORAGE_ROOT) }

# A minimal Rails application, so Active Storage's engine initializes its models,
# services and jobs exactly as it would in a real app -- without a test/dummy app to maintain.
class TestApplication < Rails::Application
  config.root = File.expand_path("..", __dir__)
  config.paths["config/database"] = "test/config/database.yml"
  config.eager_load = false
  config.logger = Logger.new(IO::NULL)
  config.secret_key_base = "mobility_active_storage_test_secret_key_base"

  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    "test" => { "service" => "Disk", "root" => STORAGE_ROOT }
  }
  config.active_job.queue_adapter = :inline

  config.i18n.available_locales = %i[en fr ja pt-BR]
  config.i18n.default_locale = :en
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
Rails.application.initialize!

require "mobility_active_storage"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:products, &:timestamps)
  create_table(:articles, &:timestamps)

  # Mobility key-value tables, so translated text attributes can share these models.
  %i[mobility_string_translations mobility_text_translations].each do |table|
    create_table table do |t|
      t.string :locale, null: false
      t.string :key, null: false
      t.send(table.to_s.include?("text") ? :text : :string, :value)
      t.integer :translatable_id, null: false
      t.string :translatable_type, null: false
      t.timestamps
      t.index %i[translatable_id translatable_type locale key],
              unique: true, name: "index_#{table}_on_keys"
    end
  end

  create_table :active_storage_blobs do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
    t.index [:key], unique: true
  end

  create_table :active_storage_attachments do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true, index: false
    t.bigint :blob_id, null: false
    t.datetime :created_at, null: false
    t.index [:blob_id]
    t.index %i[record_type record_id name blob_id],
            name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table :active_storage_variant_records do |t|
    t.belongs_to :blob, null: false, index: false
    t.string :variation_digest, null: false
    t.index %i[blob_id variation_digest],
            name: "index_active_storage_variant_records_uniqueness", unique: true
  end
end

Mobility.configure do
  plugins do
    backend :key_value
    active_record
    reader
    writer
    backend_reader
    cache
    presence
    locale_accessors
    fallbacks
  end
end

require_relative "support/models"

require "minitest/autorun"

module MobilityActiveStorage
  # Shared helpers for building attachables and asserting on stored rows.
  class TestCase < Minitest::Test
    def teardown
      ActiveStorage::Attachment.delete_all
      ActiveStorage::Blob.delete_all
      ActiveRecord::Base.connection.execute("DELETE FROM products")
      ActiveRecord::Base.connection.execute("DELETE FROM articles")
      ActiveRecord::Base.connection.execute("DELETE FROM mobility_string_translations")
      ActiveRecord::Base.connection.execute("DELETE FROM mobility_text_translations")
      Mobility.locale = :en
    end

    # Builds an attachable hash suitable for `attach` / assignment.
    def file(name, content: nil)
      { io: StringIO.new(content || "contents of #{name}"),
        filename: name,
        content_type: "application/pdf" }
    end

    def attachment_names_for(record)
      ActiveStorage::Attachment
        .where(record_type: record.class.name, record_id: record.id)
        .pluck(:name).sort
    end
  end
end
