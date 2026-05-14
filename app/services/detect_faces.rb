# frozen_string_literal: true

require 'mime/types'

module FaceCloak
  # Service object to analyze an image with Gemini and create face records
  class DetectFaces
    def self.call(image:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      image_data = GetImageRawFile.call(image_id: image.id)
      mime_type = MIME::Types.type_for(image.file_name).first&.content_type || 'application/octet-stream'
      image_path = ImageStorage.local_path(image.file_data.to_s)

      # 1. Prefer local face detection for stable coordinates; Gemini is fallback.
      faces = detect_faces(image_path, image_data, mime_type)

      # 2. Map coordinates and add Padding
      faces.each do |face_data|
        # Extract components from the new structure
        ymin = face_data[:y_min]
        xmin = face_data[:x_min]
        ymax = face_data[:y_max]
        xmax = face_data[:x_max]
        landmarks = face_data[:landmarks]

        # Convert 0-1000 to 0.0-1.0
        xmin /= 1000.0
        ymin /= 1000.0
        xmax /= 1000.0
        ymax /= 1000.0

        # Add 10% Padding
        w = xmax - xmin
        h = ymax - ymin
        xmin = [0.0, xmin - (w * 0.1)].max
        ymin = [0.0, ymin - (h * 0.1)].max
        xmax = [1.0, xmax + (w * 0.1)].min
        ymax = [1.0, ymax + (h * 0.1)].min

        face_record_data = {
          image_id: image.id,
          x_min: xmin, y_min: ymin, x_max: xmax, y_max: ymax
        }
        face_record_data[:landmarks] = landmarks.to_json if landmarks && !landmarks.empty?

        CreateFaceRecord.call(
          face_data: face_record_data,
          actor_id: image.owner_id
        )
      end
    rescue StandardError => e
      raise "Detection Error: #{e.message}"
    end

    def self.detect_faces(image_path, image_data, mime_type)
      faces = FaceDetector.call(image_path:)
      return faces unless faces.empty?

      GeminiApi.detect_faces(image_data, mime_type)
    rescue StandardError => e
      FaceCloak::Api.logger.warn("Local face detection skipped: #{e.message}")
      GeminiApi.detect_faces(image_data, mime_type)
    end
  end
end
