# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module FaceCloak
  # Service object to upload a new image and automatically detect faces
  class UploadImage
    def self.call(image_data:) # rubocop:disable Metrics/MethodLength
      owner_id = image_data['owner_id']
      original_name = image_data['file_name']
      temp_path = image_data['file_data']

      # 1. Store the original file as is (no conversion here to ensure speed/success)
      ext = File.extname(original_name).downcase
      storage_filename = "#{SecureRandom.uuid}#{ext}"
      dest_path = File.join(Image::STORAGE_DIR, storage_filename)

      FileUtils.mkdir_p(Image::STORAGE_DIR)
      FileUtils.cp(temp_path, dest_path)

      # 2. Save to Database
      new_image = Image.create(
        owner_id: owner_id,
        file_name: original_name,
        file_data: storage_filename
      )

      # 3. Trigger immediate face detection
      DetectFaces.call(image: new_image)

      # 4. PRE-WARM CACHE (This will handle format conversion internally if needed)
      new_image.refresh
      CloakImage.call(image: new_image)

      new_image
    end
  end
end
