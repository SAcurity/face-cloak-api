# frozen_string_literal: true

module FaceCloak
  # Service object to update a face record's cloak type and log the response
  class RespondToFaceRecord
    def self.call(face_record_id:, cloak_type:, actor_id:, skip_render: false)
      face_record = FaceRecord[face_record_id] || raise('Face record not found')

      face_record.cloak_type = cloak_type
      face_record.responded_at = Time.now
      face_record.save_changes

      # CRITICAL: Clear all cache for this image
      full_cache = File.join(CloakImage::CACHE_DIR, "full_#{face_record.image_id}_*.png")
      Dir.glob(full_cache).each { |f| FileUtils.rm_f(f) }

      # Rebuild the protected image immediately so the response succeeds or fails here.
      # When `skip_render` is true (used during seeding), skip the expensive
      # rendering step which may invoke external AI services.
      CloakImage.call(image: face_record.image) unless skip_render

      # Wait a tiny bit for DB to settle during high-load tests
      sleep 0.1
      face_record.add_audit_log(action: 'respond', actor_id:)

      face_record
    end
  end
end
