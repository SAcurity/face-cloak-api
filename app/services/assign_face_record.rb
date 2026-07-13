# frozen_string_literal: true

module FaceCloak
  # Service object to assign a face record to a user
  class AssignFaceRecord
    class ForbiddenError < StandardError; end

    def self.call(face_record_id:, assigned_user_id:, actor_id:)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')
      assignee_id = normalize_assignee_id(assigned_user_id)

      assignee = Account[assignee_id]
      raise Sequel::NoMatchingRow, 'Account not found' unless assignee

      # Atomically assign face
      perform_assignment(face_record, assignee.id, actor_id)
      CloakImage.clear_cached_image(face_record.image_id)

      face_record
    rescue Sequel::UniqueConstraintViolation
      raise ForbiddenError, 'User is already assigned to a face in this image'
    end

    def self.normalize_assignee_id(assigned_user_id)
      raise ArgumentError, 'assigned_user_id is required' if assigned_user_id.to_s.empty?
      raise ArgumentError, 'assigned_user_id must be an integer' unless assigned_user_id.to_s.match?(/\A\d+\z/)

      assigned_user_id.to_i
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
        face_record.add_audit_log(action: 'assign', actor_id:)
      end
    end
  end
end
