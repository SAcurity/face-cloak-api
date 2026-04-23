# frozen_string_literal: true

module FaceCloak
  # Defines the supported masking options for a detected face.
  module CloakType
    OPTIONS = %w[blur pixelate comic sunglasses mask unveil].freeze
    DEFAULT = 'blur'

    module_function

    def valid?(value)
      OPTIONS.include?(value.to_s)
    end

    def normalize(value)
      candidate = value.to_s
      return DEFAULT if candidate.empty?

      candidate
    end
  end
end
