# frozen_string_literal: true

require 'json'
require 'sequel'
require 'securerandom'

module FaceCloak
  # Represents one detected face and its masking lifecycle.
  class FaceRecord < Sequel::Model
    unrestrict_primary_key
    many_to_one :image
    one_to_many :action_logs
    plugin :association_dependencies, action_logs: :destroy

    plugin :timestamps, update_on_create: true
    plugin :whitelist_security
    set_allowed_columns :image_id, :assigned_user_id, :cloak_type

    # Secure getters and setters
    def assigned_user_id
      SecureDB.decrypt(assigned_user_id_secure)
    end

    def assigned_user_id=(plaintext)
      self.assigned_user_id_secure = SecureDB.encrypt(plaintext)
    end

    def before_create
      self.id = SecureRandom.uuid
      super
    end

    def validate
      super
      return unless cloak_type && !CloakType.valid?(cloak_type)

      errors.add(:cloak_type, "must be one of #{CloakType::OPTIONS.join(', ')}")
    end

    def assign_to(user_id, at: self.class.timestamp)
      self.assigned_user_id = user_id
      self.assigned_at = at
      self
    end

    def assigned?
      !assigned_user_id.nil? && !assigned_user_id.empty?
    end

    def clear_assignment
      raise 'Face record is not assigned' unless assigned?

      self.assigned_user_id = nil
      self.assigned_at = nil
      self.responded_at = nil
      self.cloak_type = CloakType::DEFAULT
      self
    end

    def respond_with(cloak_type, at: self.class.timestamp)
      self.responded_at ||= at
      self.cloak_type = CloakType.normalize(cloak_type)
      self
    end

    def effective_cloak_type
      responded_at.nil? ? CloakType::DEFAULT : cloak_type
    end

    def self.timestamp
      # use taiwan time
      Time.now.getlocal('+08:00')
    end

    # rubocop:disable Metrics/MethodLength
    def to_h
      {
        type: 'face_record',
        attributes: {
          id:,
          image_id:,
          assigned_user_id:,
          assigned_at:,
          responded_at:,
          cloak_type:,
          updated_at:
        }
      }
    end
    # rubocop:enable Metrics/MethodLength

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end
  end
end
