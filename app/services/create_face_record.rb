# frozen_string_literal: true

module FaceCloak
  # Service object to create a face record and log the action
  class CreateFaceRecord
    def self.call(face_data:, actor_id:)
      # 1. Create the face record
      new_face = FaceRecord.new(face_data)
      raise 'Could not save face record' unless new_face.save_changes

      # 2. Log creation
      new_face.add_action_log(action: 'create', actor_id:)

      new_face
    rescue Sequel::MassAssignmentRestriction
      raise 'Illegal attributes for face record'
    rescue StandardError => e
      raise e.message
    end
  end
end
