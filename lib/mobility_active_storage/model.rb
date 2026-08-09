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

    # Attribute names declared through the attachment macros, including any inherited from a
    # superclass. Used to keep attachments out of the hashes Mobility's attribute_methods plugin
    # builds; see {AttributeMethodsExclusion}.
    def translated_attachment_attribute_names
      @translated_attachment_attribute_names ||=
        if superclass.respond_to?(:translated_attachment_attribute_names)
          superclass.translated_attachment_attribute_names.dup
        else
          []
        end
    end

    private

    def translated_attachment(name, backend, fallbacks, locales, attached_options)
      extend Mobility unless singleton_class.include?(Mobility)

      enabled = enabled_mobility_plugins

      translates name, **{
        backend: backend,
        locales: locales,
        attachment_fallbacks: fallbacks,
        attached_options: attached_options
      }.merge(plugin_overrides(locales, enabled))
    end

    # Mobility plugins that assume a scalar value, and so must be turned off per attribute.
    # Only keys for plugins actually enabled are returned: Mobility raises InvalidOptionKey for
    # an option belonging to a plugin that is not loaded.
    def plugin_overrides(locales, enabled)
      overrides = {}

      # The fallbacks plugin consumes the `fallback:` read option before the backend sees it,
      # and triggers only on a nil read -- but an attachment reader must always return a proxy.
      # This gem implements attachment fallbacks itself instead.
      overrides[:fallbacks] = false if enabled.include?(:fallbacks)

      # The cache plugin would memoize a proxy that was resolved through a fallback, so a later
      # attach in the current locale would keep returning the fallback locale's file.
      overrides[:cache] = false if enabled.include?(:cache)

      # Dirty tracking compares scalar values; attachment proxies are not comparable.
      overrides[:dirty] = false if enabled.include?(:dirty)

      # Keep locale accessors in step with the locales we actually declared attachments for.
      overrides[:locale_accessors] = locales if locales && enabled.include?(:locale_accessors)

      overrides
    end

    def enabled_mobility_plugins
      Mobility.translations_class.included_plugins.map { |plugin| Mobility::Plugins.lookup_name(plugin) }
    end
  end
end
