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

    setup do |attributes, options, backend_class|
      attributes.each do |attribute|
        options[:locales].each do |locale|
          has_many_attached :"#{attribute}_#{Mobility.normalize_locale(locale)}",
                            **options[:attached_options]
        end

        scope :"with_attached_#{attribute}", lambda {
          name = backend_class.attachment_name_for(attribute, Mobility.locale)
          includes("#{name}_attachments": :blob)
        }

        define_method(:"#{attribute}_locales") { mobility_backends[attribute].locales }
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

      ActiveStorage::Attached::Changes::CreateMany.new(
        name, model, attachables,
        pending_uploads: model.attachment_changes[name].try(:pending_uploads)
      )
    end
  end
end
