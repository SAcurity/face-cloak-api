# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an audit log for actions performed on face records.
  class ActionLog < Sequel::Model
    many_to_one :face_record
    many_to_one :actor, class: :'FaceCloak::Account'
    many_to_one :assigned_user, class: :'FaceCloak::Account', key: :assigned_user_id
    plugin :timestamps, update_on_create: true
    plugin :whitelist_security
    set_allowed_columns :face_record_id, :actor_id, :action, :assigned_user_id, :cloak_type

    def validate
      super
      errors.add(:action, "must be one of #{ActionType::OPTIONS.join(', ')}") unless ActionType.valid?(action)
      errors.add(:cloak_type, "must be one of #{CloakType::OPTIONS.join(', ')}") if
        cloak_type && !CloakType.valid?(cloak_type)
    end

    def to_h
      {
        type: 'action_log',
        attributes: log_attributes
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end

    private

    def log_attributes
      {
        id:,
        face_record_id:,
        actor_id:,
        action:,
        created_at:
      }.merge(face_state_attributes)
    end

    def face_state_attributes
      {
        assigned_user_id:,
        assigned_user: assigned_user_summary,
        cloak_type:
      }
    end

    def assigned_user_summary
      return nil unless assigned_user

      {
        id: assigned_user.id,
        username: assigned_user.username
      }
    end
  end
end
