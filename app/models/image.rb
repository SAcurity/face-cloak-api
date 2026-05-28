# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an image that can contain multiple face records.
  class Image < Sequel::Model
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
        attributes: image_attributes
      }
    end

    def image_attributes
      {
        id:,
        owner_id:,
        owner: owner_summary,
        file_name:,
        face_ids: ordered_face_records.map(&:id),
        created_at:
      }
    end

    def owner_summary
      return nil unless owner

      {
        id: owner.id,
        username: owner.username
      }
    end

    def ordered_face_records
      face_records_dataset.order(Sequel.asc(:x_min), Sequel.asc(:y_min), Sequel.asc(:id)).all
    end

    def privacy_hash
      # FORCE reload of associations to ensure we get the LATEST settings
      # from the database, bypassing Sequel's association cache.
      latest_faces = face_records_dataset.all

      settings = latest_faces.sort_by(&:id).map do |f|
        "#{f.id}:#{f.effective_cloak_type}"
      end.join('|')
      Digest::SHA256.hexdigest(settings)[0..12]
    end

    def to_json(options = {})
      JSON(to_h, options)
    end
  end
end
