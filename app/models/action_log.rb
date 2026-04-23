# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an audit log for actions performed on face records.
  class ActionLog < Sequel::Model
    many_to_one :face_record
    plugin :timestamps, update_on_create: true
    plugin :whitelist_security
    set_allowed_columns :face_record_id, :actor_id, :action

    # Secure getters and setters
    def actor_id
      SecureDB.decrypt(actor_id_secure)
    end

    def actor_id=(plaintext)
      self.actor_id_secure = SecureDB.encrypt(plaintext)
    end

    def validate
      super
      errors.add(:action, "must be one of #{ActionType::OPTIONS.join(', ')}") unless ActionType.valid?(action)
    end

    def to_h
      {
        type: 'action_log',
        attributes: {
          id:,
          face_record_id:,
          actor_id:,
          action:,
          created_at:
        }
      }
    end

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end
  end
end
