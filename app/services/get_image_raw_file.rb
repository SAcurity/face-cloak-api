# frozen_string_literal: true

module FaceCloak
  # Service object to retrieve raw binary data of an image
  class GetImageRawFile
    def self.call(image_id:)
      image = Image[image_id] || raise('Image not found')
      raise 'Stored image file is missing' unless ImageStorage.exist?(image.file_data.to_s)

      ImageStorage.get(image.file_data.to_s)
    end
  end
end
