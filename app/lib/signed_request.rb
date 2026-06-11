# frozen_string_literal: true

require 'base64'
require 'rbnacl'

module FaceCloak
  # Verifies client-signed JSON request bodies.
  class SignedRequest
    class VerificationError < StandardError; end
    class KeypairError < StandardError; end

    def self.setup(verify_key64, signing_key64 = nil)
      @verify_key = Base64.strict_decode64(verify_key64)
      @signing_key = signing_key64.to_s.empty? ? nil : Base64.strict_decode64(signing_key64)
    rescue StandardError
      raise KeypairError, 'Invalid verification/signing keypair'
    end

    def self.generate_keypair
      signing_key = RbNaCl::SigningKey.generate
      verify_key = signing_key.verify_key

      {
        signing_key: Base64.strict_encode64(signing_key),
        verify_key: Base64.strict_encode64(verify_key)
      }
    end

    def self.parse(signed)
      data = signed[:data] || signed['data']
      signature = signed[:signature] || signed['signature']

      data if verify(data, signature)
    end

    def self.sign(message)
      raise KeypairError, 'No signing key configured' unless @signing_key

      signature = RbNaCl::SigningKey.new(@signing_key)
                                    .sign(message.to_json)
                                    .then { |sig| Base64.strict_encode64(sig) }

      { data: message, signature: }
    end

    def self.verify(message, signature64)
      signature = Base64.strict_decode64(signature64)
      verifier = RbNaCl::VerifyKey.new(@verify_key)

      verifier.verify(signature, message.to_json)
    rescue StandardError
      raise VerificationError
    end
  end
end
