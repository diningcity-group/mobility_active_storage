# frozen_string_literal: true

module MobilityActiveStorage
  # Class macros mixed into ActiveRecord::Base.
  module Model
    # Declares a single translated attachment.
    #
    #   class Product < ApplicationRecord
    #     has_one_translated_attached :document
    #     has_one_translated_attached :manual, fallbacks: true, service: :s3
    #   end
    #
    # @param name [Symbol] attribute name
    # @param fallbacks [Boolean, Hash] +true+ to fall back through I18n's chain, or an explicit
    #   hash such as <tt>{ fr: :en }</tt>. Defaults to no fallback.
    # @param locales [Array<Symbol>, nil] locales to declare attachments for. Defaults to
    #   +Mobility.available_locales+ at the time the class body runs.
    # @param attached_options [Hash] forwarded to +has_one_attached+ (+:service+,
    #   +:strict_loading+, +:dependent+).
    def has_one_translated_attached(name, fallbacks: false, locales: nil, **attached_options)
      translated_attachment(name, :active_storage, fallbacks, locales, attached_options)
    end

    # Declares a translated collection of attachments. Options match
    # {#has_one_translated_attached}; +attached_options+ is forwarded to +has_many_attached+.
    def has_many_translated_attached(name, fallbacks: false, locales: nil, **attached_options)
      translated_attachment(name, :active_storage_many, fallbacks, locales, attached_options)
    end

    private

    def translated_attachment(name, backend, fallbacks, locales, attached_options)
      extend Mobility unless singleton_class.include?(Mobility)

      options = {
        backend: backend,
        locales: locales,
        attachment_fallbacks: fallbacks,
        attached_options: attached_options
      }

      enabled = enabled_mobility_plugins

      # Mobility's fallbacks plugin consumes the `fallback:` read option before the backend
      # sees it, and triggers only on a nil read -- but an attachment reader must always
      # return a proxy. This gem implements attachment fallbacks itself instead.
      options[:fallbacks] = false if enabled.include?(:fallbacks)

      # The cache plugin would memoize a proxy that was resolved through a fallback, so a
      # later attach in the current locale would keep returning the fallback locale's file.
      options[:cache] = false if enabled.include?(:cache)

      # Dirty tracking compares scalar values; attachment proxies are not comparable.
      options[:dirty] = false if enabled.include?(:dirty)

      # Keep locale accessors in step with the locales we actually declared attachments for.
      options[:locale_accessors] = locales if locales && enabled.include?(:locale_accessors)

      translates name, **options
    end

    def enabled_mobility_plugins
      Mobility.translations_class.included_plugins.map { |plugin| Mobility::Plugins.lookup_name(plugin) }
    end
  end
end
