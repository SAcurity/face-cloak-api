# frozen_string_literal: true

require_relative 'securable'

module FaceCloak
  # Encrypt and Decrypt from Database
  class SecureDB
    extend Securable

    class NoDbKeyError < StandardError; end
    class NoHashKeyError < StandardError; end

    def self.setup(db_key, hash_key)
      raise NoDbKeyError unless db_key
      raise NoHashKeyError unless hash_key

      setup_secret_key(db_key)
      setup_hash_key(hash_key)
    end

    # Encrypt or else return nil if data is nil
    def self.encrypt(plaintext)
      base_encrypt(plaintext)
    end

    # Decrypt or else return nil if database value is nil already
    def self.decrypt(ciphertext64)
      base_decrypt(ciphertext64)
    end

    # Keyed hash for deterministic lookup on encrypted columns
    def self.hash(plaintext)
      base_hash(plaintext)
    end
  end
end
