# frozen_string_literal: true

module FaceCloak
  # Service object to upload a new image and automatically detect faces
  class UploadImage
    def self.call(image_data:) # rubocop:disable Metrics/MethodLength
      # 1. Store file physically using storage service
      storage_result = StoreImageFile.call(
        owner_id: image_data['owner_id'],
        file_name: image_data['file_name'],
        file_data: image_data['file_data']
      )

      # 2. Build the record
      new_image = Image.new(
        owner_id: image_data['owner_id'],
        file_name: storage_result[:file_name],
        file_data: storage_result[:storage_key]
      )

      # 3. Persist and automate detection
      new_image.db.transaction do
        raise 'Could not save image record' unless new_image.save_changes

        detect_faces(new_image)
      end

      new_image
    rescue Sequel::MassAssignmentRestriction
      raise 'Illegal attributes for image'
    rescue StandardError => e
      raise e.message
    end

    def self.detect_faces(image)
      2.times do
        CreateFaceRecord.call(
          face_data: { image_id: image.id, cloak_type: 'blur' },
          actor_id: image.owner_id
        )
      end
    end
  end
end
