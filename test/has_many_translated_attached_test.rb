# frozen_string_literal: true

require "test_helper"

module MobilityActiveStorage
  class HasManyTranslatedAttachedTest < TestCase
    def setup
      @product = Product.create!(title: "Widget")
    end

    def test_returns_an_attached_many_proxy
      assert_kind_of ActiveStorage::Attached::Many, @product.photos
    end

    def test_is_empty_before_anything_is_attached
      refute_predicate @product.photos, :attached?
      assert_empty @product.photos
    end

    def test_attaches_multiple_files_in_the_current_locale
      @product.photos.attach(file("a.pdf"), file("b.pdf"))
      @product.reload

      assert_equal %w[a.pdf b.pdf], @product.photos.map { |p| p.filename.to_s }.sort
    end

    def test_attach_appends_rather_than_replaces
      @product.photos.attach(file("a.pdf"))
      @product.photos.attach(file("b.pdf"))
      @product.reload

      assert_equal 2, @product.photos.count
    end

    def test_assignment_replaces_the_whole_set
      @product.photos.attach(file("a.pdf"), file("b.pdf"))
      @product.photos = [file("c.pdf")]
      @product.save!
      @product.reload

      assert_equal %w[c.pdf], @product.photos.map { |p| p.filename.to_s }
    end

    def test_stores_the_locale_in_the_attachment_name
      @product.photos.attach(file("a.pdf"))
      Mobility.with_locale(:fr) { @product.photos.attach(file("b.pdf")) }

      assert_equal %w[photos_en photos_fr], attachment_names_for(@product)
    end

    def test_collections_are_isolated_per_locale
      @product.photos.attach(file("a.pdf"), file("b.pdf"))
      Mobility.with_locale(:fr) { @product.photos.attach(file("c.pdf")) }
      @product.reload

      assert_equal 2, @product.photos.count
      assert_equal 1, Mobility.with_locale(:fr) { @product.photos.count }
      assert_empty Mobility.with_locale(:ja) { @product.photos }
    end

    def test_locale_accessors
      Mobility.with_locale(:fr) { @product.photos.attach(file("c.pdf")) }
      @product.reload

      assert_equal %w[c.pdf], @product.photos_fr.map { |p| p.filename.to_s }
      assert_empty @product.photos_en
    end

    def test_assignment_on_an_unsaved_record_is_staged_until_save
      product = Product.new(title: "New")
      product.photos = [file("a.pdf"), file("b.pdf")]

      refute_predicate ActiveStorage::Attachment, :any?

      product.save!

      assert_equal 2, product.reload.photos.count
    end

    def test_purging_affects_only_the_current_locale
      @product.photos.attach(file("a.pdf"))
      Mobility.with_locale(:fr) { @product.photos.attach(file("b.pdf")) }

      Mobility.with_locale(:fr) { @product.photos.purge }
      @product.reload

      assert_equal 1, @product.photos.count
      assert_empty @product.photos_fr
    end

    def test_reports_locales_that_have_attachments
      @product.photos.attach(file("a.pdf"))
      Mobility.with_locale(:ja) { @product.photos.attach(file("b.pdf")) }
      @product.reload

      assert_equal %i[en ja], @product.photos_locales.sort
    end

    # A collection repeats its name once per file, so the lookup has to be distinct or a locale
    # with three photos would be yielded three times.
    def test_locales_yields_a_locale_once_however_many_files_it_holds
      @product.photos.attach(file("a.pdf"), file("b.pdf"), file("c.pdf"))
      product = Product.find(@product.id)

      statements = queries_for { assert_equal %i[en], product.photos_locales }

      assert_equal 1, statements.size, statements.join("\n")
    end

    def test_locales_counts_files_staged_but_not_yet_saved
      Mobility.with_locale(:fr) { @product.photos.attach(file("fr.pdf")) }

      assert_equal %i[fr], @product.photos_locales
    end

    def test_locales_drops_a_detachment_staged_but_not_yet_saved
      @product.photos.attach(file("a.pdf"))
      @product.reload
      @product.photos = []

      assert_empty @product.photos_locales
    end

    def test_destroying_the_record_purges_every_locale
      @product.photos.attach(file("a.pdf"))
      Mobility.with_locale(:fr) { @product.photos.attach(file("b.pdf")) }

      @product.destroy

      assert_empty attachment_names_for(@product)
    end

    def test_eager_loading_scope_rejects_an_unconfigured_locale
      error = assert_raises(MobilityActiveStorage::Error) do
        Mobility.with_locale(:ja) { LimitedManyProduct.with_attached_photos.to_a }
      end

      assert_match(/ja/, error.message)
    end

    def test_exposes_the_underlying_rails_associations_and_scopes
      assert Product.reflect_on_association(:photos_en_attachments)
      assert Product.reflect_on_association(:photos_en_blobs)
      assert_respond_to Product, :with_attached_photos_en
    end
  end
end
