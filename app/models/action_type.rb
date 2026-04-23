# frozen_string_literal: true

module FaceCloak
  # Defines the supported actions that can be performed on a face record.
  module ActionType
    OPTIONS = %w[create assign unassign respond].freeze

    module_function

    def valid?(value)
      OPTIONS.include?(value.to_s)
    end

    def normalize(value)
      value.to_s
    end
  end
end
