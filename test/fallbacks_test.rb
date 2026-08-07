# frozen_string_literal: true

require "test_helper"

module MobilityActiveStorage
  class FallbacksTest < TestCase
    def test_no_fallback_by_default
      product = Product.create!
      product.document.attach(file("en.pdf"))
      product.reload

      refute_predicate Mobility.with_locale(:fr) { product.document }, :attached?
    end

    def test_falls_back_to_the_default_locale_when_enabled
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      Mobility.with_locale(:fr) do
        assert_predicate product.document, :attached?
        assert_equal "en.pdf", product.document.filename.to_s
      end
    end

    def test_prefers_the_current_locale_over_the_fallback
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { product.document.attach(file("fr.pdf")) }
      product.reload

      assert_equal "fr.pdf", Mobility.with_locale(:fr) { product.document.filename.to_s }
    end

    def test_follows_an_explicit_fallback_chain
      product = ExplicitFallbackProduct.create!
      Mobility.with_locale(:fr) { product.document.attach(file("fr.pdf")) }
      product.reload

      # ja falls back to fr, then en
      assert_equal "fr.pdf", Mobility.with_locale(:ja) { product.document.filename.to_s }
    end

    def test_returns_an_empty_proxy_when_no_locale_has_an_attachment
      product = FallbackProduct.create!

      Mobility.with_locale(:fr) do
        refute_predicate product.document, :attached?
        assert_kind_of ActiveStorage::Attached::One, product.document
      end
    end

    def test_an_empty_fallback_proxy_can_still_be_attached_to
      product = FallbackProduct.create!

      Mobility.with_locale(:fr) { product.document.attach(file("fr.pdf")) }
      product.reload

      assert_equal %w[document_fr], attachment_names_for(product)
    end

    def test_attaching_never_writes_to_the_fallback_locale
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      Mobility.with_locale(:fr) { product.document.attach(file("fr.pdf")) }
      product.reload

      assert_equal "en.pdf", product.document.filename.to_s
      assert_equal %w[document_en document_fr], attachment_names_for(product)
    end

    def test_purging_through_a_fallback_leaves_the_fallback_locale_alone
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      # :fr has nothing of its own, so this purge must be a no-op rather than purging :en.
      Mobility.with_locale(:fr) { product.document.purge }
      product.reload

      assert_predicate product.document, :attached?
      assert_equal %w[document_en], attachment_names_for(product)
    end

    def test_detaching_through_a_fallback_leaves_the_fallback_locale_alone
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      Mobility.with_locale(:fr) { product.document.detach }
      product.reload

      assert_predicate product.document, :attached?
    end

    def test_attaching_through_a_fallback_does_not_copy_the_fallback_collection
      product = FallbackProduct.create!
      product.photos.attach(file("a.pdf"), file("b.pdf"))
      product.reload

      Mobility.with_locale(:fr) { product.photos.attach(file("c.pdf")) }
      product.reload

      assert_equal 2, product.photos.count
      assert_equal %w[c.pdf], product.photos_fr.map { |p| p.filename.to_s }
    end

    def test_purging_a_collection_through_a_fallback_leaves_the_fallback_locale_alone
      product = FallbackProduct.create!
      product.photos.attach(file("a.pdf"))
      product.reload

      Mobility.with_locale(:fr) { product.photos.purge }
      product.reload

      assert_equal 1, product.photos.count
    end

    def test_a_fallback_read_still_reports_the_expected_proxy_type
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      Mobility.with_locale(:fr) do
        assert_kind_of ActiveStorage::Attached::One, product.document
      end
    end

    def test_fallback_can_be_bypassed_per_call
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      Mobility.with_locale(:fr) do
        refute_predicate product.document(fallback: false), :attached?
      end
    end

    def test_predicate_respects_fallbacks
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      assert Mobility.with_locale(:fr) { product.document? }
    end

    def test_locales_reports_only_locales_actually_attached
      product = FallbackProduct.create!
      product.document.attach(file("en.pdf"))
      product.reload

      assert_equal %i[en], product.document_locales
    end

    def test_fallbacks_for_has_many
      product = FallbackProduct.create!
      product.photos.attach(file("a.pdf"), file("b.pdf"))
      product.reload

      assert_equal 2, Mobility.with_locale(:fr) { product.photos.count }
      assert_empty Mobility.with_locale(:fr) { product.photos(fallback: false) }
    end
  end
end
