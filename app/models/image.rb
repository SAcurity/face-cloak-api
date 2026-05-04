# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an image that can contain multiple face records.
  class Image < Sequel::Model
    STORAGE_DIR = 'db/local/storage'

    unrestrict_primary_key
    one_to_many :face_records
    many_to_many :assignees,
                 class: :'FaceCloak::Account',
                 join_table: :accounts_images,
                 left_key: :image_id,
                 right_key: :account_id
    many_to_one :owner, class: :'FaceCloak::Account'

    plugin :association_dependencies, face_records: :destroy, assignees: :nullify

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :id, :owner_id, :file_name, :file_data

    def before_create
      self.id ||= SecureRandom.uuid
      super
    end

    def to_h
      {
        type: 'image',
        attributes: {
          id:,
          owner_id:,
          file_name:,
          file_data:
        }
      }
    end

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end
  end
end
