# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an audit log for actions performed on face records.
  class ActionLog < Sequel::Model
    many_to_one :face_record
    many_to_one :actor, class: :'FaceCloak::Account'
    plugin :timestamps, update_on_create: true
    plugin :whitelist_security
    set_allowed_columns :face_record_id, :actor_id, :action

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
