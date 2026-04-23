# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test SecureDB Library' do
  it 'HAPPY: should encrypt and decrypt data correctly' do
    plaintext = 'secret message'
    ciphertext = FaceCloak::SecureDB.encrypt(plaintext)

    _(ciphertext).wont_equal plaintext
    _(FaceCloak::SecureDB.decrypt(ciphertext)).must_equal plaintext
  end

  it 'SAD: should return nil if decrypting nil' do
    _(FaceCloak::SecureDB.decrypt(nil)).must_be_nil
  end
end
