# frozen_string_literal: true

module MobilityActiveStorage
  # Attached proxies used when a read resolves through a fallback locale.
  #
  # Reads (+attached?+, +filename+, +url+, iteration) resolve to the fallback locale's
  # attachment, but every write -- +attach+, +purge+, +purge_later+, +detach+ -- stays bound to
  # the locale actually being read. Without that split, +product.document.attach(file)+ under a
  # fallback would overwrite the fallback locale's file instead of creating one for the
  # current locale.
  #
  # The classes are built lazily: Active Storage's classes are autoloaded by its engine, which
  # has not necessarily run at the point this gem is required from a Gemfile.
  module FallbackAttached
    class << self
      def one
        @one ||= const_set(:One, build(::ActiveStorage::Attached::One) do
          # The fallback locale's attachment stands in when this locale has none.
          def attachment
            own.attachment || record.public_send(:"#{fallback_name}_attachment")
          end
        end)
      end

      def many
        @many ||= const_set(:Many, build(::ActiveStorage::Attached::Many) do
          def attachments
            own.attachments.presence || record.public_send(:"#{fallback_name}_attachments")
          end

          def blobs
            own.blobs.presence || record.public_send(:"#{fallback_name}_blobs")
          end
        end)
      end

      private

      def build(plain_class, &reads)
        Class.new(plain_class) do
          attr_reader :fallback_name

          define_method(:initialize) do |name, record, fallback_name|
            super(name, record)
            @fallback_name = fallback_name
          end

          # This locale as an ordinary Active Storage proxy. Writes delegate here so that
          # Rails' own logic runs, bound to this locale's attachment name.
          define_method(:own) { plain_class.new(name, record) }

          def attach(*attachables) = own.attach(*attachables)
          def purge = own.purge
          def purge_later = own.purge_later
          def detach = own.detach

          class_eval(&reads)
        end
      end
    end
  end
end
