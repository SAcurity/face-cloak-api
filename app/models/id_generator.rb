# frozen_string_literal: true

require 'base64'
require 'rbnacl'

module FaceCloak
  # Generates opaque identifiers for user-facing records.
  module IdGenerator
    module_function

    def next_id(prefix:)
      raw = RbNaCl::Random.random_bytes(12)
      token = Base64.urlsafe_encode64(raw, padding: false)
      "#{prefix}_#{token}"
    end
  end
end
