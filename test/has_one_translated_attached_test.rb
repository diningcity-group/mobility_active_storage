# frozen_string_literal: true

require "test_helper"

module MobilityActiveStorage
  class HasOneTranslatedAttachedTest < TestCase
    def setup
      @product = Product.create!(title: "Widget")
    end

    def test_returns_an_attached_one_proxy
      assert_kind_of ActiveStorage::Attached::One, @product.document
    end

    def test_is_not_attached_before_anything_is_attached
      refute_predicate @product.document, :attached?
      refute @product.document?
    end

    def test_attaches_in_the_current_locale
      @product.document.attach(file("en.pdf"))
      @product.reload

      assert_predicate @product.document, :attached?
      assert_equal "en.pdf", @product.document.filename.to_s
      assert @product.document?
    end

    def test_stores_the_locale_in_the_attachment_name
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }

      assert_equal %w[document_en document_fr], attachment_names_for(@product)
    end

    def test_normalizes_dashed_locales_in_the_attachment_name
      Mobility.with_locale(:"pt-BR") { @product.document.attach(file("pt.pdf")) }

      assert_equal %w[document_pt_br], attachment_names_for(@product)
    end

    def test_attachments_are_isolated_per_locale
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }
      @product.reload

      assert_equal "en.pdf", @product.document.filename.to_s
      assert_equal "fr.pdf", Mobility.with_locale(:fr) { @product.document.filename.to_s }
      refute_predicate Mobility.with_locale(:ja) { @product.document }, :attached?
    end

    def test_locale_accessors_read_a_specific_locale
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }
      @product.reload

      assert_equal "fr.pdf", @product.document_fr.filename.to_s
      refute_predicate @product.document_en, :attached?
    end

    def test_locale_accessor_writers_attach_to_that_locale
      @product.document_fr = file("fr.pdf")
      @product.save!
      @product.reload

      assert_equal "fr.pdf", @product.document_fr.filename.to_s
      assert_equal %w[document_fr], attachment_names_for(@product)
    end

    def test_assignment_on_an_unsaved_record_is_staged_until_save
      product = Product.new(title: "New")
      product.document = file("staged-en.pdf")
      product.document_fr = file("staged-fr.pdf")

      refute_predicate ActiveStorage::Attachment, :any?

      product.save!
      product.reload

      assert_equal "staged-en.pdf", product.document.filename.to_s
      assert_equal "staged-fr.pdf", product.document_fr.filename.to_s
    end

    def test_locale_specific_predicate
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }
      @product.reload

      assert @product.document_fr?
      refute @product.document_en?
    end

    def test_attaching_to_an_unsaved_record_is_staged_until_save
      product = Product.new(title: "New")
      product.document.attach(file("staged.pdf"))

      assert_predicate product.document, :attached?
      assert_equal 0, ActiveStorage::Attachment.count

      product.save!

      assert_equal "staged.pdf", product.reload.document.filename.to_s
    end

    def test_can_be_passed_to_create
      product = Product.create!(title: "C", document: file("c.pdf"))

      assert_equal "c.pdf", product.reload.document.filename.to_s
    end

    def test_replacing_an_attachment_in_one_locale
      @product.document.attach(file("first.pdf"))
      @product.document.attach(file("second.pdf"))
      @product.reload

      assert_equal "second.pdf", @product.document.filename.to_s
      assert_equal %w[document_en], attachment_names_for(@product)
    end

    def test_purging_affects_only_the_current_locale
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }

      Mobility.with_locale(:fr) { @product.document.purge }
      @product.reload

      assert_predicate @product.document, :attached?
      refute_predicate @product.document_fr, :attached?
      assert_equal %w[document_en], attachment_names_for(@product)
    end

    def test_assigning_nil_detaches_that_locale
      @product.document.attach(file("en.pdf"))
      @product.document = nil
      @product.save!
      @product.reload

      refute_predicate @product.document, :attached?
    end

    def test_reports_locales_that_have_attachments
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:ja) { @product.document.attach(file("ja.pdf")) }
      @product.reload

      assert_equal %i[en ja], @product.document_locales.sort
    end

    def test_locales_is_empty_when_nothing_is_attached
      assert_empty @product.document_locales
    end

    def test_destroying_the_record_purges_every_locale
      @product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { @product.document.attach(file("fr.pdf")) }

      @product.destroy

      assert_empty attachment_names_for(@product)
    end

    def test_exposes_the_underlying_rails_associations_and_scopes
      assert Product.reflect_on_association(:document_en_attachment)
      assert Product.reflect_on_association(:document_en_blob)
      assert_respond_to Product, :with_attached_document_en
    end

    def test_eager_loading_scope_for_the_current_locale
      @product.document.attach(file("en.pdf"))

      product = Product.with_attached_document.find(@product.id)

      assert_predicate product.association(:document_en_attachment), :loaded?
    end

    def test_works_without_an_explicit_extend_mobility
      article = Article.create!
      article.cover.attach(file("cover.pdf"))
      Mobility.with_locale(:fr) { article.cover.attach(file("couverture.pdf")) }
      article.reload

      assert_equal "cover.pdf", article.cover.filename.to_s
      assert_equal "couverture.pdf", article.cover_fr.filename.to_s
    end

    def test_restricting_the_locale_set
      assert_respond_to LimitedProduct.new, :document_fr

      # With Mobility's fallthrough_accessors plugin enabled, method_missing answers for any
      # locale-shaped name, so the guarantee is the raise rather than the missing method.
      assert_raises(MobilityActiveStorage::Error) { LimitedProduct.new.document_ja }
    end

    # The eager-loading scope must fail the same way the read path does, rather than leaking a
    # confusing ActiveRecord::AssociationNotFoundError about a generated association name.
    def test_eager_loading_scope_rejects_an_unconfigured_locale
      LimitedProduct.create!

      error = assert_raises(MobilityActiveStorage::Error) do
        Mobility.with_locale(:ja) { LimitedProduct.with_attached_document.to_a }
      end

      assert_match(/ja/, error.message)
    end

    def test_attaching_an_unconfigured_locale_raises
      product = LimitedProduct.create!

      error = assert_raises(MobilityActiveStorage::Error) do
        Mobility.with_locale(:ja) { product.document.attach(file("ja.pdf")) }
      end

      assert_match(/ja/, error.message)
    end
  end
end
