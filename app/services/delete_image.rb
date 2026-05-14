# frozen_string_literal: true

require 'fileutils'

module FaceCloak
  # Service object to delete an image record and its physical file
  class DeleteImage
    def self.call(image_id:)
      image = Image[image_id] || raise('Image not found')

      image.db.transaction do
        # 1. Delete from DB (cascades to face_records and action_logs via plugin)
        raise 'Could not delete image record' unless image.destroy

        # 2. Cleanup stored object
        ImageStorage.delete(image.file_data.to_s)
      end

      true
    rescue StandardError => e
      raise e.message
    end
  end
end
