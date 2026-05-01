# frozen_string_literal: true

module FaceCloak
  # Service object to update a face record's cloak type and log the response
  class RespondToFaceRecord
    def self.call(face_record_id:, cloak_type:, actor_id:)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')

      face_record.update(
        cloak_type:,
        responded_at: Time.now
      )

      # Log action
      face_record.add_action_log(action: 'respond', actor_id:)

      face_record
    end
  end
end
