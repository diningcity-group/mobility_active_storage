# frozen_string_literal: true

require "test_helper"

module MobilityActiveStorage
  # Mobility's attribute_methods plugin merges every translated attribute into `attributes`.
  # For an attachment that value is a live ActiveStorage proxy holding a reference back to the
  # record, which makes the hash unserialisable and unusable for mass assignment. Rails' own
  # has_one_attached puts nothing in `attributes`, and neither should this gem.
  class AttributeMethodsTest < TestCase
    def setup
      @product = Product.create!(title: "Widget", description: "A widget")
      @product.document.attach(file("en.pdf"))
      @product.photos.attach(file("a.pdf"), file("b.pdf"))
      @product.reload
    end

    def test_attachment_attributes_are_absent_from_attributes
      keys = @product.attributes.keys

      refute_includes keys, "document"
      refute_includes keys, "photos"
    end

    def test_attributes_holds_no_active_storage_proxy
      values = @product.attributes.values

      refute(values.any? { |v| v.is_a?(ActiveStorage::Attached) })
    end

    # Article declares only a translated attachment, so its attributes should be exactly what
    # Rails' has_one_attached gives -- both tables carry just the timestamps.
    def test_attachment_only_model_matches_plain_has_one_attached
      assert_equal PlainProduct.new.attributes.keys.sort, Article.new.attributes.keys.sort
    end

    # A model with both kinds keeps the translated text attributes and drops the attachments.
    def test_attributes_adds_only_translated_text_attributes
      extra = Product.new.attributes.keys - PlainProduct.new.attributes.keys

      assert_equal %w[description title], extra.sort
    end

    def test_attributes_can_be_serialised_to_json
      json = @product.attributes.to_json

      assert_kind_of String, json
      assert_includes json, "Widget"
    end

    def test_as_json_can_be_serialised
      json = @product.as_json

      refute_includes json.keys, "document"
      refute_includes json.keys, "photos"
      assert_kind_of String, json.to_json
    end

    def test_attributes_can_be_passed_to_a_new_record
      copy = Product.new(@product.attributes.except("id", "created_at", "updated_at"))

      assert_equal "Widget", copy.title
    end

    def test_to_json_on_the_record_itself
      assert_kind_of String, @product.to_json
    end

    def test_translated_attachment_attributes_are_absent_from_translated_attributes
      keys = @product.translated_attributes.keys

      refute_includes keys, "document"
      refute_includes keys, "photos"
    end

    # Translated *text* attributes must keep working exactly as Mobility defines them.
    def test_translated_text_attributes_remain_in_attributes
      assert_equal "Widget", @product.attributes["title"]
      assert_equal "A widget", @product.translated_attributes["description"]
    end

    def test_attachment_names_are_absent_from_serialization_names
      names = @product.send(:attribute_names_for_serialization)

      refute_includes names, "document"
      refute_includes names, "photos"
      assert_includes names, "title"
    end

    def test_serializable_hash_excludes_attachments
      hash = @product.serializable_hash

      refute_includes hash.keys, "document"
      refute_includes hash.keys, "photos"
    end

    # The exclusion must survive a translates call made after the attachment macro, which
    # inserts a new Mobility module at higher precedence than anything included earlier.
    def test_exclusion_survives_a_later_translates_call
      record = LateTranslatesProduct.create!(title: "Late")
      record.document.attach(file("late.pdf"))
      record.reload

      refute_includes record.attributes.keys, "document"
      assert_equal "Late", record.attributes["title"]
      assert_kind_of String, record.attributes.to_json
    end

    # Everything the gem actually exposes must be untouched by the fix.
    def test_attachment_api_is_unaffected
      assert_equal "en.pdf", @product.document.filename.to_s
      assert_equal 2, @product.photos.count
      assert @product.document?
      assert_equal %i[en], @product.document_locales

      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }
      @product.reload

      assert_equal "fr.pdf", @product.document_fr.filename.to_s
      assert_equal %w[document_en document_fr photos_en photos_en],
                   attachment_names_for(@product)
    end

    # The exclusion lives in the backend's setup block, not the macro, so declaring the backend
    # directly through `translates` is covered too.
    def test_exclusion_applies_when_the_backend_is_declared_directly
      record = DirectBackendProduct.create!
      record.document.attach(file("direct.pdf"))
      record.reload

      refute_includes record.attributes.keys, "document"
      assert_kind_of String, record.attributes.to_json
      assert_equal "direct.pdf", record.document.filename.to_s
    end

    # Mobility's query plugin is enabled by its default initializer, and asks the backend for an
    # Arel node. Attachments have no comparable column, so this must explain itself.
    def test_querying_an_attachment_raises_a_clear_error
      error = assert_raises(MobilityActiveStorage::Error) do
        MobilityActiveStorage::Backend["document", :en]
      end

      assert_match(/not comparable|cannot query/, error.message)
      assert_match(/document/, error.message)
    end

    def test_purge_still_works_after_the_fix
      @product.document.purge
      @product.reload

      refute_predicate @product.document, :attached?
    end
  end
end
