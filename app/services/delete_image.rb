# frozen_string_literal: true

require 'fileutils'

module FaceCloak
  # Service object to delete an image record and its physical file
  class DeleteImage
    def self.call(image_id:)
      image = Image[image_id] || raise('Image not found')
      storage_path = File.join(Image::STORAGE_DIR, image.file_data.to_s)

      image.db.transaction do
        # 1. Delete from DB (cascades to face_records and action_logs via plugin)
        raise 'Could not delete image record' unless image.destroy

        # 2. Cleanup physical file
        FileUtils.rm_f(storage_path)
      end

      true
    rescue StandardError => e
      raise e.message
    end
  end
end
