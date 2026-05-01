# frozen_string_literal: true

module FaceCloak
  # Service object to assign a face record to a user and grant image access
  class AssignFaceRecord
    class ForbiddenError < StandardError; end

    def self.call(face_record_id:, assigned_user_id:, actor_id:)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')

      # 1. Constraint: ANY user can only be assigned to ONE face record per image
      ensure_unique_assignment(face_record, assigned_user_id)

      # 2. Atomically assign face and grant image access
      perform_assignment(face_record, assigned_user_id, actor_id)

      face_record
    end

    def self.ensure_unique_assignment(face_record, assigned_user_id)
      already_assigned = face_record.image.face_records.any? do |fr|
        fr.assigned_user_id == assigned_user_id.to_i && fr.id != face_record.id
      end
      raise ForbiddenError, 'User is already assigned to a face in this image' if already_assigned
    end

    def self.perform_assignment(face_record, assigned_user_id, actor_id) # rubocop:disable Metrics/MethodLength
      face_record.db.transaction do
        face_record.update(
          assigned_user_id:,
          assigned_at: Time.now
        )

        # Grant image access (Join table: accounts_images)
        assignee_id_int = assigned_user_id.to_i
        assignee = Account[assignee_id_int]
        raise 'Account not found' unless assignee

        face_record.image.add_assignee(assignee) unless face_record.image.assignees.include?(assignee)

        # Log action
        face_record.add_action_log(action: 'assign', actor_id:)
      end
    end
  end
end
