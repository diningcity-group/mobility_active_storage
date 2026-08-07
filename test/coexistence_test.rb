# frozen_string_literal: true

require "test_helper"

module MobilityActiveStorage
  # Translated attachments must sit alongside ordinary Mobility text attributes
  # on the same model without either interfering with the other.
  class CoexistenceTest < TestCase
    def setup
      @product = Product.create!(title: "Widget", description: "A widget")
    end

    def test_translated_text_attributes_still_work
      Mobility.with_locale(:fr) do
        @product.title = "Gadget"
        @product.description = "Un gadget"
        @product.save!
      end
      @product.reload

      assert_equal "Widget", @product.title
      assert_equal "Gadget", @product.title_fr
      assert_equal "Un gadget", @product.description_fr
    end

    def test_text_and_attachments_translate_together
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) do
        @product.title = "Gadget"
        @product.document.attach(file("fr.pdf"))
        @product.save!
      end
      @product.reload

      Mobility.with_locale(:fr) do
        assert_equal "Gadget", @product.title
        assert_equal "fr.pdf", @product.document.filename.to_s
      end

      assert_equal "Widget", @product.title
      assert_equal "en.pdf", @product.document.filename.to_s
    end

    def test_a_single_create_can_set_both
      product = Product.create!(title: "Both", document: file("both.pdf"))
      product.reload

      assert_equal "Both", product.title
      assert_equal "both.pdf", product.document.filename.to_s
    end

    def test_mobility_reports_all_translated_attributes
      names = Product.mobility_attributes

      assert_includes names, "title"
      assert_includes names, "document"
      assert_includes names, "photos"
    end

    def test_the_attachment_backend_is_registered_under_its_own_name
      assert_equal MobilityActiveStorage::Backend, Mobility::Backends.load_backend(:active_storage)
      assert_equal MobilityActiveStorage::ManyBackend,
                   Mobility::Backends.load_backend(:active_storage_many)
    end

    def test_the_backend_can_be_used_through_translates_directly
      record = DirectBackendProduct.create!
      record.document.attach(file("direct.pdf"))
      Mobility.with_locale(:fr) { record.document.attach(file("direct-fr.pdf")) }
      record.reload

      assert_equal "direct.pdf", record.document.filename.to_s
      assert_equal "direct-fr.pdf", record.document_fr.filename.to_s
    end

    def test_destroying_cleans_up_both_translations_and_attachments
      Mobility.with_locale(:fr) do
        @product.title = "Gadget"
        @product.save!
      end
      @product.document.attach(file("en.pdf"))

      @product.destroy

      assert_empty attachment_names_for(@product)
      assert_equal 0, ActiveStorage::Attachment.count
    end
  end
end
