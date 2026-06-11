# frozen_string_literal: true

require 'fileutils'

module FaceCloak
  # Service object to let an assignee decline a face assignment.
  class DeclineFaceRecord
    def self.call(face_record_id:, actor_id:)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')
      ensure_assignee!(face_record, actor_id)

      face_record.db.transaction do
        face_record.update(declined_attributes)
        face_record.add_audit_log(action: 'decline', actor_id: actor_id.to_i)
      end

      clear_cached_image(face_record.image_id)
      face_record
    end

    def self.ensure_assignee!(face_record, actor_id)
      return if actor_id.to_i == face_record.assigned_user_id

      raise Api::ForbiddenRequest, 'You are not assigned to this face record'
    end

    def self.declined_attributes
      {
        assigned_user_id: nil,
        assigned_at: nil,
        responded_at: nil,
        cloak_type: CloakType::DEFAULT
      }
    end

    def self.clear_cached_image(image_id)
      full_cache = File.join(CloakImage::CACHE_DIR, "full_#{image_id}_*.png")
      Dir.glob(full_cache).each { |file| FileUtils.rm_f(file) }
    end
  end
end
