# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceCloak::SignedRequest' do
  let(:keypair) { FaceCloak::SignedRequest.generate_keypair }
  let(:payload) { { username: 'alice', password: 'password123' } }

  before do
    @config_keys = %i[@verify_key @signing_key].map do |var|
      FaceCloak::SignedRequest.instance_variable_get(var)
    end
  end

  after do
    FaceCloak::SignedRequest.instance_variable_set(:@verify_key, @config_keys[0])
    FaceCloak::SignedRequest.instance_variable_set(:@signing_key, @config_keys[1])
  end

  it 'SECURITY: should generate a Base64-encoded Ed25519 keypair' do
    _(Base64.strict_decode64(keypair[:signing_key]).bytesize).must_equal 32
    _(Base64.strict_decode64(keypair[:verify_key]).bytesize).must_equal 32
  end

  it 'SECURITY: should round-trip a signed request' do
    FaceCloak::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])

    signed = FaceCloak::SignedRequest.sign(payload)

    _(signed[:data]).must_equal payload
    _(signed[:signature]).must_be_kind_of String
    _(FaceCloak::SignedRequest.parse(signed)).must_equal payload
  end

  it 'SECURITY: should reject forged or tampered signatures' do
    FaceCloak::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])
    signed = FaceCloak::SignedRequest.sign(payload)
    forger = FaceCloak::SignedRequest.generate_keypair
    forged_signature = Base64.strict_encode64(
      RbNaCl::SigningKey.new(Base64.strict_decode64(forger[:signing_key]))
                         .sign(payload.to_json)
    )

    _ { FaceCloak::SignedRequest.parse(data: payload, signature: forged_signature) }
      .must_raise FaceCloak::SignedRequest::VerificationError
    _ { FaceCloak::SignedRequest.parse(data: { username: 'attacker' }, signature: signed[:signature]) }
      .must_raise FaceCloak::SignedRequest::VerificationError
  end

  it 'SECURITY: should reject missing signatures' do
    FaceCloak::SignedRequest.setup(keypair[:verify_key])

    _ { FaceCloak::SignedRequest.parse(data: payload) }
      .must_raise FaceCloak::SignedRequest::VerificationError
  end

  it 'SECURITY: should reject invalid key setup' do
    _ { FaceCloak::SignedRequest.setup('not-base64') }
      .must_raise FaceCloak::SignedRequest::KeypairError
  end

  it 'SECURITY: should refuse signing when setup has only a verify key' do
    FaceCloak::SignedRequest.setup(keypair[:verify_key])

    _ { FaceCloak::SignedRequest.sign(payload) }
      .must_raise FaceCloak::SignedRequest::KeypairError
  end
end
