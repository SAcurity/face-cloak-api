# frozen_string_literal: true

require 'fileutils'
require 'mime/types'
require 'securerandom'

module FaceCloak
  # Service object to upload a new image and automatically detect faces
  class UploadImage
    def self.call(image_data:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      owner_id = image_data['owner_id']
      original_name = image_data['file_name']
      temp_path = image_data['file_data']
      file_name = unique_file_name(owner_id, original_name)

      # 1. Store the original file as is (no conversion here to ensure speed/success)
      ext = File.extname(file_name).downcase
      storage_filename = "images/#{SecureRandom.uuid}#{ext}"

      FileUtils.mkdir_p(Image::STORAGE_DIR)
      ImageStorage.put_file(storage_filename, temp_path, content_type: content_type_for(file_name))

      # 2. Save to Database
      new_image = Image.create(
        owner_id: owner_id,
        file_name: file_name,
        file_data: storage_filename
      )

      # 3. Run detection synchronously by default so face records are persisted
      # before the upload response returns.
      detect_after_upload(new_image)

      new_image
    rescue Sequel::UniqueConstraintViolation
      ImageStorage.delete(storage_filename) if storage_filename
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      retry
    end

    def self.content_type_for(file_name)
      MIME::Types.type_for(file_name).first&.content_type || 'application/octet-stream'
    end

    def self.detect_after_upload(image)
      return DetectFaces.call(image:) unless async_detection?

      Thread.new(image.id) do |image_id|
        DetectFaces.call(image: Image[image_id])
      rescue StandardError => e
        FaceCloak::Api.logger.warn("Face detection skipped for image #{image_id}: #{e.message}")
      end
    end

    def self.async_detection?
      FaceCloak::Api.environment == :production && ENV.fetch('ASYNC_FACE_DETECTION', nil) == 'true'
    end

    def self.unique_file_name(owner_id, file_name)
      return file_name unless Image.where(owner_id:, file_name:).any?

      ext = File.extname(file_name)
      basename = File.basename(file_name, ext)
      counter = 1

      loop do
        candidate = "#{basename}-#{counter}#{ext}"
        return candidate unless Image.where(owner_id:, file_name: candidate).any?

        counter += 1
      end
    end
  end
end
