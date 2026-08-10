# frozen_string_literal: true

require "i18n/locale/fallbacks"

module MobilityActiveStorage
  # Behaviour shared by the has_one and has_many attachment backends.
  #
  # A translated attachment is stored as N ordinary Active Storage attachments whose
  # +name+ column carries the locale, e.g. +document_en+ and +document_fr+. Each one is
  # declared with a real +has_one_attached+ / +has_many_attached+ in the backend's setup
  # block, so Rails' own associations, upload callbacks, scopes and purge-on-destroy
  # behaviour apply unchanged.
  #
  # Backends must +include Mobility::Backend+ *before* this module, so that the overrides here
  # (notably +each_locale+ and +present?+) take precedence over Mobility::Backend's generic
  # implementations.
  module BackendMethods
    def self.included(base)
      raise Error, "#{base} must include Mobility::Backend before #{self}" unless base < Mobility::Backend

      base.extend(ClassMethods)
    end

    # Class-level configuration shared by both backends.
    module ClassMethods
      def valid_keys
        %i[locales attachment_fallbacks attached_options]
      end

      def configure(options)
        options[:locales] = Array(options[:locales] || Mobility.available_locales).map(&:to_sym)
        options[:attached_options] ||= {}
        options[:attachment_fallbacks] = build_fallbacks(options[:attachment_fallbacks])
      end

      # Locale-suffixed attachment name, rejecting locales this attribute was not configured
      # for. Shared by the read path and by the eager-loading scopes, so both fail the same way
      # rather than the scope leaking an ActiveRecord::AssociationNotFoundError about a
      # generated association name.
      def attachment_name_for(attribute, locale)
        normalized = Mobility.normalize_locale(locale)
        return "#{attribute}_#{normalized}" if normalized_locales.include?(normalized)

        raise Error, "#{model_class.name} has no translated #{attribute} attachment for " \
                     "locale #{locale.inspect}. Configured locales: " \
                     "#{options[:locales].map(&:to_s).join(", ")}."
      end

      def configured_locale?(locale)
        normalized_locales.include?(Mobility.normalize_locale(locale))
      end

      # Every configured locale's attachment name. Memoized per attribute: the locale set is
      # fixed when the class body runs.
      def attachment_names(attribute)
        @attachment_names ||= {}
        @attachment_names[attribute] ||= normalized_locales.map { |locale| "#{attribute}_#{locale}" }
      end

      # Mobility's query plugin asks the backend for an Arel node so it can build a predicate.
      # An attachment is a row in active_storage_attachments, not a comparable column value, so
      # there is nothing meaningful to compare. Fail with an explanation rather than the
      # NoMethodError a missing `[]` would otherwise produce.
      def [](name, _locale)
        raise Error, "cannot query translated attachment #{name} -- attachments are not " \
                     "comparable values. Query ActiveStorage::Attachment directly, filtering " \
                     "on name (for example \"#{name}_#{Mobility.normalize_locale}\")."
      end

      def normalized_locales
        @normalized_locales ||= options[:locales].map { |locale| Mobility.normalize_locale(locale) }
      end

      private

      def build_fallbacks(option)
        case option
        when true then FallbackChain.new({})
        when Hash then FallbackChain.new(option)
        else false
        end
      end
    end

    # Resolves a locale to the chain of locales to try, in order.
    #
    # Mirrors Mobility's own fallbacks plugin: an explicit map is honoured first, then I18n's
    # configured fallbacks when the application has them enabled, and the default locale always
    # terminates the chain. Resolved on each read so that changes to +I18n.default_locale+ or
    # +I18n.fallbacks+ are picked up.
    class FallbackChain
      def initialize(map)
        @fallbacks = I18n::Locale::Fallbacks.new(map)
      end

      def [](locale)
        chain = @fallbacks[locale]
        chain |= I18n.fallbacks[locale] if I18n.respond_to?(:fallbacks)
        chain | [I18n.default_locale]
      end
    end

    # Returns the Active Storage proxy for +locale+.
    #
    # Always returns a proxy, never nil, so that +record.document.attach(...)+ works on a
    # record with nothing attached yet. Falls back to another locale only when the attribute
    # was configured with fallbacks and the current locale has nothing attached.
    #
    # @param [Symbol] locale
    # @return [ActiveStorage::Attached::One, ActiveStorage::Attached::Many]
    def read(locale, fallback: true, **kwargs)
      proxy = attached(locale)
      return proxy if proxy.attached?

      # Mobility's convention: an explicitly requested locale never falls back.
      return proxy if fallback == false || kwargs[:locale]

      fallback_locale = fallback_chain(locale, fallback).find do |candidate|
        configured?(candidate) && attached(candidate).attached?
      end
      return proxy unless fallback_locale

      # Reads resolve through the fallback locale; writes stay in the requested locale.
      fallback_attached_class.new(attachment_name(locale), model, attachment_name(fallback_locale))
    end

    # Stages the attachment change for +locale+.
    #
    # Deliberately mutates +attachment_changes+ rather than calling +attach+.
    # +ActiveStorage::Attached::One#attach+ is implemented as
    # +record.public_send("document_en=", attachable)+, and Mobility's locale accessors take
    # precedence over Active Storage's generated writer -- so calling +attach+ here would
    # re-enter this same method. Writing the change directly makes both entry paths converge.
    def write(locale, value, **)
      name = attachment_name(locale)
      model.attachment_changes[name] = build_change(name, value)
      value
    end

    # Whether the attribute has an attachment in +locale+ (honouring fallbacks).
    def present?(locale, **options)
      read(locale, **options).attached?
    end

    # Yields each configured locale that actually has an attachment.
    #
    # One query for the whole locale set, not one per locale: every locale is a row in
    # active_storage_attachments under a suffixed name, so which locales are present is a single
    # pluck on that table. Probing each proxy instead costs a query per configured locale, and a
    # model declared for a large locale set pays that on every read -- 73 statements to answer a
    # question one statement answers.
    #
    # Pending changes win over the stored rows, as Active Storage's own +attached?+ does: an
    # attach counts before it is saved, a purge stops counting straight away.
    def each_locale
      persisted = persisted_attachment_names

      options[:locales].each do |locale|
        name = attachment_name(locale)
        # attached? reads the staged change without touching the database.
        present = model.attachment_changes.key?(name) ? attached(locale).attached? : persisted.include?(name)
        yield locale if present
      end
    end

    # The Active Storage proxy for +locale+, without any fallback handling.
    def attached(locale)
      @attached ||= {}
      @attached[Mobility.normalize_locale(locale)] ||=
        attached_class.new(attachment_name(locale), model)
    end

    private

    # Which of this attribute's attachment names have rows. distinct because a collection
    # attachment repeats its name once per file, and polymorphic_name so an STI subclass looks
    # itself up under the type Active Storage actually stored.
    def persisted_attachment_names
      return Set.new if model.new_record?

      ActiveStorage::Attachment
        .where(record_type: model.class.polymorphic_name, record_id: model.id,
               name: self.class.attachment_names(attribute))
        .distinct
        .pluck(:name)
        .to_set
    end

    def attachment_name(locale)
      self.class.attachment_name_for(attribute, locale)
    end

    def configured?(locale)
      self.class.configured_locale?(locale)
    end

    # +fallback: :fr+ or +fallback: [:fr, :es]+ overrides the configured chain for one read.
    #
    # An attribute that declares no fallbacks cannot be talked into one by a read option, so a
    # +fallbacks: false+ declaration is enforceable: otherwise any reader that forwards
    # caller-controlled options (a serializer, a GraphQL resolver) would become a cross-locale
    # read. This matches Mobility, whose fallbacks plugin is inert when +fallbacks: false+.
    def fallback_chain(locale, fallback)
      fallbacks = options[:attachment_fallbacks]
      return [] unless fallbacks
      return Array(fallback) unless fallback == true

      fallbacks[locale]
    end
  end
end
