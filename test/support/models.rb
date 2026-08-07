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

  translates :document, backend: :active_storage, fallbacks: false
end

# Restricts the locale set explicitly rather than reading Mobility.available_locales.
class LimitedProduct < ActiveRecord::Base
  self.table_name = "products"
  extend Mobility

  has_one_translated_attached :document, locales: %i[en fr]
end
