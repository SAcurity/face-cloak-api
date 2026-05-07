# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Authentication' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
    @account_data = { username: 'testuser', email: 'test@example.com', password: 'password123' }
    @account = create_account(@account_data[:username], @account_data[:email], @account_data[:password])
  end

  it 'HAPPY: should authenticate valid credentials' do
    creds = { username: @account_data[:username], password: @account_data[:password] }
    post 'api/v1/auth/authenticate', creds.to_json, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'account'
    _(result['attributes']['id']).must_equal @account.id
    _(result['attributes']['username']).must_equal @account_data[:username]
    _(result['attributes']['email']).must_equal @account_data[:email]
    _(result['include']['face_assignments']).must_be_kind_of Array
    _(result['include']['system_roles']).must_be_kind_of Array
  end

  it 'BAD: should reject invalid password' do
    creds = { username: @account_data[:username], password: 'wrong_password' }
    post 'api/v1/auth/authenticate', creds.to_json, @req_header
    _(last_response.status).must_equal 403

    result = JSON.parse last_response.body
    _(result['message']).must_equal 'Invalid credentials'
    _(result['attributes']).must_be_nil
  end

  it 'BAD: should reject unknown username' do
    creds = { username: 'nonexistent', password: 'password123' }
    post 'api/v1/auth/authenticate', creds.to_json, @req_header
    _(last_response.status).must_equal 403
  end
end
