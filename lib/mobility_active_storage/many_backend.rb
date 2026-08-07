# frozen_string_literal: true

require_relative "backend_methods"

module MobilityActiveStorage
  # Mobility backend for a translated collection of Active Storage attachments.
  #
  # @example
  #   class Product < ApplicationRecord
  #     extend Mobility
  #     translates :photos, backend: :active_storage_many
  #   end
  #
  #   product.photos.attach(first, second)
  #   Mobility.with_locale(:fr) { product.photos.attach(other) }
  class ManyBackend
    include Mobility::Backend
    include BackendMethods

    setup do |attributes, options|
      attributes.each do |attribute|
        options[:locales].each do |locale|
          has_many_attached :"#{attribute}_#{Mobility.normalize_locale(locale)}",
                            **options[:attached_options]
        end

        scope :"with_attached_#{attribute}", lambda {
          includes("#{attribute}_#{Mobility.normalize_locale}_attachments": :blob)
        }

        define_method(:"#{attribute}_locales") { mobility_backends[attribute].locales }
      end
    end

    class << self
      # +pending_uploads:+ was added to CreateMany after Rails 7.0.
      def supports_pending_uploads?
        return @supports_pending_uploads if defined?(@supports_pending_uploads)

        @supports_pending_uploads =
          ActiveStorage::Attached::Changes::CreateMany.instance_method(:initialize)
                                                      .parameters.any? { |(_, n)| n == :pending_uploads }
      end
    end

    private

    def attached_class
      ActiveStorage::Attached::Many
    end

    def fallback_attached_class
      FallbackAttached.many
    end

    # Mirrors the writer that has_many_attached generates, including carrying pending uploads
    # across successive assignments so `attach` can append to an unsaved record.
    def build_change(name, value)
      attachables = Array(value).compact_blank

      return ActiveStorage::Attached::Changes::DeleteMany.new(name, model) if attachables.none?

      if self.class.supports_pending_uploads?
        pending = model.attachment_changes[name].try(:pending_uploads)
        ActiveStorage::Attached::Changes::CreateMany.new(name, model, attachables,
                                                         pending_uploads: pending)
      else
        ActiveStorage::Attached::Changes::CreateMany.new(name, model, attachables)
      end
    end
  end
end
