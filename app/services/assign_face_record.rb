# frozen_string_literal: true

module FaceCloak
  # Service object to assign a face record to a user
  class AssignFaceRecord
    class ForbiddenError < StandardError; end

    def self.call(face_record_id:, assigned_user_id:, actor_id:)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')

      # Verify account exists
      assignee = Account[assigned_user_id.to_i]
      raise 'Account not found' unless assignee

      # Atomically assign face
      perform_assignment(face_record, assignee.id, actor_id)

      face_record
    rescue Sequel::UniqueConstraintViolation
      raise ForbiddenError, 'User is already assigned to a face in this image'
    end

    def self.perform_assignment(face_record, assigned_user_id, actor_id)
      face_record.db.transaction do
        face_record.update(
          assigned_user_id:,
          assigned_at: Time.now
        )

        # Explicitly link account to image in join table for easier access control and clear DB schema
        assignee = Account[assigned_user_id]
        face_record.image.add_assignee(assignee) unless face_record.image.assignees.include?(assignee)

        # Log action
        face_record.add_action_log(action: 'assign', actor_id:)
      end
    end
  end
end
