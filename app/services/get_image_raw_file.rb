# frozen_string_literal: true

module FaceCloak
  # Service object to retrieve raw binary data of an image
  class GetImageRawFile
    def self.call(image_id:)
      image = Image[image_id] || raise('Image not found')
      storage_path = File.join(Image::STORAGE_DIR, image.file_data.to_s)
      raise 'Stored image file is missing' unless File.exist?(storage_path)

      File.binread(storage_path)
    end
  end
end
