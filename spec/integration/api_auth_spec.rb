# frozen_string_literal: true

require_relative '../spec_helper'
require 'openssl'
require 'webmock/minitest'

describe 'Test Authentication' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
    @account_data = { username: 'testuser', email: 'test@example.com', password: 'password123' }
    @account = create_account(@account_data[:username], @account_data[:email], @account_data[:password])
  end

  def rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def jwks
    { keys: [JWT::JWK.new(rsa_key.public_key, kid: 'test-kid').export] }
  end

  def google_id_token(overrides = {})
    JWT.encode(google_claims(overrides), rsa_key, 'RS256', kid: 'test-kid')
  end

  def google_claims(overrides = {})
    now = Time.now.to_i
    {
      aud: FaceCloak::Api.config.GOOGLE_CLIENT_ID, iss: 'https://accounts.google.com',
      sub: 'google-sub-123', email: 'sso@example.com',
      email_verified: true, name: 'SSO User',
      picture: 'https://example.com/avatar.png',
      exp: now + 300, iat: now
    }.merge(overrides)
  end

  it 'HAPPY: should authenticate valid credentials' do
    creds = { username: @account_data[:username], password: @account_data[:password] }
    post 'api/v1/auth/authenticate', signed_json(creds), @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'authenticated_account'
    account = result['attributes']['account']
    _(account['type']).must_equal 'account'
    _(account['attributes']['id']).must_equal @account.id
    _(account['attributes']['username']).must_equal @account_data[:username]
    _(account['attributes']['email']).must_equal @account_data[:email]
    _(account['include']['face_assignments']).must_be_kind_of Array
    _(account['include']['system_roles']).must_be_kind_of Array
    _(result['attributes']['auth_token']).must_be_kind_of String
    _(result['attributes']['auth_token']).wont_be_empty
  end

  it 'SECURITY: returned auth_token decrypts to the authenticated account' do
    creds = { username: @account_data[:username], password: @account_data[:password] }
    post 'api/v1/auth/authenticate', signed_json(creds), @req_header

    token = JSON.parse(last_response.body)['attributes']['auth_token']
    payload = FaceCloak::AuthToken.load(token).payload
    _(payload['type']).must_equal 'account'
    _(payload['attributes']['id']).must_equal @account.id
    _(payload['attributes']['username']).must_equal @account_data[:username]
  end

  it 'BAD: should reject invalid password' do
    creds = { username: @account_data[:username], password: 'wrong_password' }
    post 'api/v1/auth/authenticate', signed_json(creds), @req_header
    _(last_response.status).must_equal 403

    result = JSON.parse last_response.body
    _(result['message']).must_equal 'Invalid credentials'
    _(result['attributes']).must_be_nil
  end

  it 'BAD: should reject unknown username' do
    creds = { username: 'nonexistent', password: 'password123' }
    post 'api/v1/auth/authenticate', signed_json(creds), @req_header
    _(last_response.status).must_equal 403
  end

  it 'SECURITY: should reject unsigned authentication requests' do
    creds = { username: @account_data[:username], password: @account_data[:password] }

    post 'api/v1/auth/authenticate', creds.to_json, @req_header

    _(last_response.status).must_equal 403
    _(JSON.parse(last_response.body)['message']).must_equal 'Must sign request'
  end

  describe 'Registration verification' do
    before do
      setup_mailgun_env
      base_url = ENV.fetch('MAILGUN_API_BASE_URL').delete_suffix('/')
      @mail_url = "#{base_url}/v3/#{ENV.fetch('MAILGUN_DOMAIN')}/messages"
      @registration = {
        email: 'someone-new@example.com',
        verification_url: 'https://app.example.com/auth/register/abc'
      }
    end

    after { WebMock.reset! }

    it 'HAPPY: returns 202 and triggers a Mailgun POST' do
      stub = stub_request(:post, @mail_url).to_return(status: 200)

      post 'api/v1/auth/register', signed_json(@registration), @req_header

      _(last_response.status).must_equal 202
      assert_requested(stub)
    end

    it 'SAD: returns 400 when email is already taken' do
      stub_request(:post, @mail_url).to_return(status: 200)
      registration = @registration.merge(email: @account_data[:email])

      post 'api/v1/auth/register', signed_json(registration), @req_header

      _(last_response.status).must_equal 400
      _(JSON.parse(last_response.body)['message']).must_equal 'Email already registered'
    end

    it 'SAD: returns 500 when Mailgun rejects the email request' do
      stub_request(:post, @mail_url).to_return(status: 503)

      post 'api/v1/auth/register', signed_json(@registration), @req_header

      _(last_response.status).must_equal 500
      _(JSON.parse(last_response.body)['message']).must_equal 'Could not send verification email'
    end

    it 'SECURITY: rejects unsigned registration requests' do
      post 'api/v1/auth/register', @registration.to_json, @req_header

      _(last_response.status).must_equal 403
    end
  end

  describe 'SSO authentication' do
    it 'HAPPY: creates a new SSO account and returns an auth token' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token, jwks: }),
           @req_header

      _(last_response.status).must_equal 200
      result = JSON.parse(last_response.body)
      _(result['type']).must_equal 'authenticated_account'
      account = result['attributes']['account']
      _(account['attributes']['username']).must_equal 'sso'
      _(account['attributes']['email']).must_equal 'sso@example.com'
      _(account['attributes']['avatar']).must_equal 'https://example.com/avatar.png'
      _(result['attributes']['auth_token']).wont_be_empty

      created = FaceCloak::Account.first(username: 'sso')
      _(created.sso_provider).must_equal 'google'
      _(created.sso_subject).must_equal 'google-sub-123'
      _(created.password?('anything')).must_equal false
    end

    it 'HAPPY: repeated SSO login reuses the existing account' do
      body = signed_json({ provider: 'google', id_token: google_id_token, jwks: })

      post 'api/v1/auth/sso', body, @req_header
      first_id = JSON.parse(last_response.body)['attributes']['account']['attributes']['id']
      post 'api/v1/auth/sso', body, @req_header
      second_id = JSON.parse(last_response.body)['attributes']['account']['attributes']['id']

      _(last_response.status).must_equal 200
      _(second_id).must_equal first_id
      _(FaceCloak::Account.where(sso_provider: 'google', sso_subject: 'google-sub-123').count).must_equal 1
    end

    it 'HAPPY: links an existing verified-email account' do
      existing = create_account('local_user', 'sso@example.com', 'password123')

      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token, jwks: }),
           @req_header

      _(last_response.status).must_equal 200
      existing.refresh
      _(existing.sso_provider).must_equal 'google'
      _(existing.sso_subject).must_equal 'google-sub-123'
      account = JSON.parse(last_response.body)['attributes']['account']
      _(account['attributes']['id']).must_equal existing.id
    end

    it 'SECURITY: rejects an id_token with the wrong audience' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token(aud: 'wrong-client'), jwks: }),
           @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: rejects an id_token with the wrong issuer' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token(iss: 'https://evil.example'), jwks: }),
           @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: rejects an id_token with no matching JWKS kid' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token, jwks: { keys: [] } }),
           @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: rejects an id_token with an invalid signature' do
      other_key = OpenSSL::PKey::RSA.generate(2048)
      forged = JWT.encode(google_claims, other_key, 'RS256', kid: 'test-kid')

      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: forged, jwks: }),
           @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: rejects an unverified email' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'google', id_token: google_id_token(email_verified: false), jwks: }),
           @req_header

      _(last_response.status).must_equal 401
    end

    it 'BAD: rejects unsupported providers' do
      post 'api/v1/auth/sso',
           signed_json({ provider: 'github', id_token: google_id_token, jwks: }),
           @req_header

      _(last_response.status).must_equal 400
    end

    it 'SECURITY: rejects unsigned SSO requests' do
      post 'api/v1/auth/sso',
           { provider: 'google', id_token: google_id_token, jwks: }.to_json,
           @req_header

      _(last_response.status).must_equal 403
    end
  end
end
