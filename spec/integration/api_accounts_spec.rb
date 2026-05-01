# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Account API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  it 'HAPPY: should be able to create a new account' do
    account_data = { username: 'alice', email: 'alice@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Account created'
    _(result['data']['attributes']['username']).must_equal 'alice'
    _(result['data']['attributes']['email']).must_equal 'alice@example.com'
  end

  it 'SAD: should not be able to create an account with existing username' do
    create_account('alice', 'alice@example.com', 'password123')
    account_data = { username: 'alice', email: 'alice2@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'already exists'
  end

  it 'HAPPY: should be able to authenticate an account' do
    create_account('alice', 'alice@example.com', 'password123')
    auth_data = { username: 'alice', password: 'password123' }

    post 'api/v1/accounts/authenticate', auth_data.to_json
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data']['attributes']['username']).must_equal 'alice'
  end

  it 'SAD: should not be able to authenticate with wrong password' do
    create_account('alice', 'alice@example.com', 'password123')
    auth_data = { username: 'alice', password: 'wrong_password' }

    post 'api/v1/accounts/authenticate', auth_data.to_json
    _(last_response.status).must_equal 401
    _(JSON.parse(last_response.body)['message']).must_include 'Invalid credentials'
  end

  it 'HAPPY: should be able to get account details' do
    create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts/alice'
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data']['attributes']['username']).must_equal 'alice'
    _(result['data']['attributes']['email']).must_equal 'alice@example.com'
  end

  it 'HAPPY: should be able to search for account by email' do
    create_account('alice', 'alice@example.com', 'password123')
    search_data = { email: 'alice@example.com' }

    post 'api/v1/accounts/search', search_data.to_json
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data']['attributes']['username']).must_equal 'alice'
  end

  it 'SAD: should return 404 for search with unknown email' do
    post 'api/v1/accounts/search', { email: 'unknown@example.com' }.to_json
    _(last_response.status).must_equal 404
  end

  it 'SAD: should return 404 for non-existent account' do
    get 'api/v1/accounts/non_existent'
    _(last_response.status).must_equal 404
  end
end
