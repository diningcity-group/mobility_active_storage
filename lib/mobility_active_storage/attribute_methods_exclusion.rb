# frozen_string_literal: true

module MobilityActiveStorage
  # Keeps translated attachments out of the attribute hashes.
  #
  # Mobility's attribute_methods plugin merges every translated attribute into +attributes+. For
  # an attachment that value is a live +ActiveStorage::Attached+ proxy holding a reference back to
  # the record, so the hash cannot be serialised (+to_json+ recurses until the stack blows) and
  # cannot be fed back into +Model.new+ (Active Storage rejects a proxy as an attachable). Rails'
  # own +has_one_attached+ puts nothing in +attributes+; this restores that.
  #
  # Overriding +translated_attributes+ also cleans +attributes+: the plugin defines the latter as
  # +super.merge(translated_attributes)+, and that inner call dispatches from the record, so it
  # reaches this module first.
  #
  # Prepended rather than included, which matters. +include+ places this module *behind* any
  # Mobility module added afterwards, and re-including an already-included module does not move it
  # forward -- so a second +translates+ call (a second attachment macro, or a later
  # +translates :title+) would merge its name back in after the filter had run. A prepended module
  # stays ahead of every later include. Verified against Ruby's method resolution, not assumed.
  module AttributeMethodsExclusion
    # Registers +attribute+ on +model_class+ and installs the filter. Called from the backends'
    # setup blocks rather than from the macros, so that declaring the backend directly with
    # `translates :document, backend: :active_storage` is covered too.
    def self.install(model_class, attribute)
      model_class.translated_attachment_attribute_names << attribute.to_s

      # Nothing to filter unless the plugin that does the merging is loaded -- and `super` in
      # #translated_attributes would have nothing to reach.
      return unless Mobility.translations_class.included_plugins
                            .map { |plugin| Mobility::Plugins.lookup_name(plugin) }
                            .include?(:attribute_methods)

      model_class.prepend(self)
    end

    def translated_attributes
      super.except(*self.class.translated_attachment_attribute_names)
    end

    private

    def attribute_names_for_serialization
      return unless defined?(super)

      super - self.class.translated_attachment_attribute_names
    end
  end
end
