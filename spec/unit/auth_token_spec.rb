# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test AuthToken Library' do
  let(:payload) { { 'type' => 'account', 'attributes' => { 'id' => 1, 'username' => 'alice' } } }

  it 'SECURITY: should produce an encrypted string token from a payload' do
    token = FaceCloak::AuthToken.new(payload).to_s

    _(token).must_be_kind_of String
    _(token).wont_be_empty
    _(token).wont_include 'alice'
  end

  it 'HAPPY: should round-trip payload data' do
    token = FaceCloak::AuthToken.new(payload).to_s
    loaded = FaceCloak::AuthToken.load(token)

    _(loaded.payload).must_equal payload
  end

  it 'HAPPY: should round-trip default full scope' do
    token = FaceCloak::AuthToken.new(payload).to_s

    _(FaceCloak::AuthToken.load(token).scope.to_s).must_equal FaceCloak::AuthScope::FULL
  end

  it 'HAPPY: should round-trip explicit read-only scope' do
    token = FaceCloak::AuthToken.new(
      payload, scope: FaceCloak::AuthScope.new(FaceCloak::AuthScope::READ_ONLY)
    ).to_s

    _(FaceCloak::AuthToken.load(token).scope.to_s).must_equal FaceCloak::AuthScope::READ_ONLY
  end

  it 'SECURITY: should reject old token shapes without scope' do
    old_token = FaceCloak::AuthToken.tokenize('payload' => payload, 'exp' => (Time.now + 60).to_i)

    _ { FaceCloak::AuthToken.load(old_token) }.must_raise FaceCloak::AuthToken::InvalidTokenError
  end

  it 'SECURITY: should expose freshness predicates' do
    auth_token = FaceCloak::AuthToken.new(payload)

    _(auth_token.fresh?).must_equal true
    _(auth_token.expired?).must_equal false
  end

  it 'SECURITY: should detect expired tokens' do
    auth_token = FaceCloak::AuthToken.new(payload, -1)

    _(auth_token.expired?).must_equal true
    _(auth_token.fresh?).must_equal false
  end

  it 'SECURITY: should raise when reading an expired token payload' do
    token = FaceCloak::AuthToken.new(payload, -1).to_s
    loaded = FaceCloak::AuthToken.load(token)

    _ { loaded.payload }.must_raise FaceCloak::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: should raise when reading an expired token scope' do
    token = FaceCloak::AuthToken.new(payload, -1).to_s
    loaded = FaceCloak::AuthToken.load(token)

    _ { loaded.scope }.must_raise FaceCloak::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: should reject malformed tokens' do
    _ { FaceCloak::AuthToken.load('not-a-real-token') }
      .must_raise FaceCloak::AuthToken::InvalidTokenError
  end

  it 'SECURITY: should reject tampered tokens' do
    token = FaceCloak::AuthToken.new(payload).to_s
    tampered = "#{token[0..-3]}XX"

    _ { FaceCloak::AuthToken.load(tampered) }
      .must_raise FaceCloak::AuthToken::InvalidTokenError
  end
end
