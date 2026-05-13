# frozen_string_literal: true

require 'json'
require 'open3'

module FaceCloak
  # Local OpenCV face detector, with Gemini fallback handled by caller.
  class FaceDetector
    SCRIPT_PATH = 'app/lib/opencv_face_detector.py'
    DEFAULT_PYTHON = '.venv/bin/python'

    def self.call(image_path:)
      return [] unless available?

      stdout, stderr, status = Open3.capture3(python_bin, SCRIPT_PATH, image_path)
      raise "OpenCV face detection failed: #{stderr.strip}" unless status.success?

      normalize(JSON.parse(stdout, symbolize_names: true))
    rescue JSON::ParserError => e
      raise "OpenCV face detection returned invalid JSON: #{e.message}"
    end

    def self.available?
      File.exist?(SCRIPT_PATH) && cv2_available?
    end

    def self.python_bin
      ENV.fetch('FACE_DETECTOR_PYTHON', File.exist?(DEFAULT_PYTHON) ? DEFAULT_PYTHON : 'python3')
    end

    def self.cv2_available?
      system(python_bin, '-c', 'import cv2', out: File::NULL, err: File::NULL)
    end

    def self.normalize(faces)
      faces.filter_map { |face| normalize_face(face) }
    end

    def self.normalize_face(face)
      box = face[:box]
      return nil unless box.is_a?(Array) && box.length == 4

      coordinates = box.map { |coordinate| Float(coordinate) }
      face_payload(coordinates, face[:landmarks])
    rescue ArgumentError, TypeError
      nil
    end

    def self.face_payload(coordinates, landmarks)
      payload = {
        y_min: coordinates[0],
        x_min: coordinates[1],
        y_max: coordinates[2],
        x_max: coordinates[3]
      }
      payload[:landmarks] = landmarks if landmarks && !landmarks.empty?
      payload
    end
  end
end
