# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents an audit log for actions performed on face records.
  class ActionLog < Sequel::Model
    many_to_one :face_record
    plugin :timestamps, update_on_create: true

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
