# frozen_string_literal: true

require_relative "backend_methods"

module MobilityActiveStorage
  # Mobility backend for a single translated Active Storage attachment.
  #
  # @example
  #   class Product < ApplicationRecord
  #     extend Mobility
  #     translates :document, backend: :active_storage
  #   end
  #
  #   product.document.attach(io: file, filename: "en.pdf", content_type: "application/pdf")
  #   Mobility.with_locale(:fr) { product.document.attach(...) }
  class Backend
    include Mobility::Backend
    include BackendMethods

    setup do |attributes, options|
      attributes.each do |attribute|
        options[:locales].each do |locale|
          has_one_attached :"#{attribute}_#{Mobility.normalize_locale(locale)}",
                           **options[:attached_options]
        end

        # Eager-loads whichever locale is current when the scope is evaluated.
        scope :"with_attached_#{attribute}", lambda {
          includes("#{attribute}_#{Mobility.normalize_locale}_attachment": :blob)
        }

        define_method(:"#{attribute}_locales") { mobility_backends[attribute].locales }
      end
    end

    private

    def attached_class
      ActiveStorage::Attached::One
    end

    def fallback_attached_class
      FallbackAttached.one
    end

    def build_change(name, value)
      if value.nil? || value == ""
        ActiveStorage::Attached::Changes::DeleteOne.new(name, model)
      else
        ActiveStorage::Attached::Changes::CreateOne.new(name, model, value)
      end
    end
  end
end
