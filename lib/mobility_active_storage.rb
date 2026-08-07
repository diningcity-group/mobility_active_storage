# frozen_string_literal: true

require "mobility"
require "active_support"

require_relative "mobility_active_storage/version"

module MobilityActiveStorage
  class Error < StandardError; end
end

require_relative "mobility_active_storage/fallback_attached"
require_relative "mobility_active_storage/backend"
require_relative "mobility_active_storage/many_backend"
require_relative "mobility_active_storage/model"

Mobility::Backends.register_backend(:active_storage, MobilityActiveStorage::Backend)
Mobility::Backends.register_backend(:active_storage_many, MobilityActiveStorage::ManyBackend)

ActiveSupport.on_load(:active_record) do
  extend MobilityActiveStorage::Model
end
