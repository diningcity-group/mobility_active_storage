# frozen_string_literal: true

# Models used across the test suite. All defined after the schema is loaded.

# The main model: translated text attributes alongside translated attachments,
# exercising the coexistence requirement.
class Product < ActiveRecord::Base
  extend Mobility

  translates :title, type: :string
  translates :description, type: :text

  has_one_translated_attached :document
  has_many_translated_attached :photos
end

# Rails' own has_one_attached, as the baseline `attributes` should match.
class PlainProduct < ActiveRecord::Base
  self.table_name = "products"

  has_one_attached :document
end

# Declares a translated text attribute *after* the attachment macro, which inserts a Mobility
# module at higher precedence than anything included at macro time.
class LateTranslatesProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_one_translated_attached :document
  translates :title, type: :string
end

# Uses the macro without an explicit `extend Mobility`.
class Article < ActiveRecord::Base
  has_one_translated_attached :cover
end

# Fallbacks enabled via Mobility/I18n defaults.
class FallbackProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_one_translated_attached :document, fallbacks: true
  has_many_translated_attached :photos, fallbacks: true
end

# Fallbacks configured explicitly.
class ExplicitFallbackProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_one_translated_attached :document, fallbacks: { fr: :en, ja: %i[fr en] }
end

# Declares the backend through `translates` directly rather than through the macro.
class DirectBackendProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  # Declaring the backend directly means opting out of the scalar-value plugins by hand;
  # the macros do this for you.
  translates :document, backend: :active_storage, fallbacks: false, cache: false, dirty: false
end

# Restricts the locale set for a collection attachment.
class LimitedManyProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_many_translated_attached :photos, locales: %i[en fr]
end

# Restricts the locale set explicitly rather than reading Mobility.available_locales.
class LimitedProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_one_translated_attached :document, locales: %i[en fr]
end
