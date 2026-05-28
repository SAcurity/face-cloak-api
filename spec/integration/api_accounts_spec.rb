# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Account API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
  end

  it 'HAPPY: should be able to create a new account' do
    account_data = { username: 'alice', email: 'alice@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json, @req_header
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Account created'
    _(result['data']['attributes']['username']).must_equal 'alice'
    _(result['data']['attributes']['email']).must_equal 'alice@example.com'
  end

  it 'HAPPY: should be able to get list of all accounts' do
    alice = create_account('alice', 'alice@example.com', 'password123')
    create_account('bob', 'bob@example.com', 'password123')

    get 'api/v1/accounts', nil, auth_request_header(alice)
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].map { |a| a['username'] }).must_include 'alice'
    _(result['data'].first).must_include 'policies'
  end

  it 'SAD: should require authentication to get list of all accounts' do
    create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts', nil, @req_header
    _(last_response.status).must_equal 401
  end

  it 'SAD: should not be able to create an account with existing username' do
    create_account('alice', 'alice@example.com', 'password123')
    account_data = { username: 'alice', email: 'alice2@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json, @req_header
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'already exists'
  end

  it 'SAD: should not be able to create an account with existing email' do
    create_account('alice', 'alice@example.com', 'password123')
    account_data = { username: 'alice2', email: 'alice@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json, @req_header
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'already exists'
  end

  it 'HAPPY: should be able to get account details' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts/alice', nil, auth_request_header(alice)
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['type']).must_equal 'account'
    _(result['attributes']['username']).must_equal 'alice'
    _(result['attributes']['email']).must_equal 'alice@example.com'
    _(result).must_include 'policies'
  end

  it 'HAPPY: should be able to search for account by email' do
    create_account('alice', 'alice@example.com', 'password123')
    search_data = { email: 'alice@example.com' }

    post 'api/v1/accounts/search', search_data.to_json, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['type']).must_equal 'account'
    _(result['attributes']['username']).must_equal 'alice'
  end

  it 'SAD: should return 404 for search with unknown email' do
    post 'api/v1/accounts/search', { email: 'unknown@example.com' }.to_json, @req_header
    _(last_response.status).must_equal 404
  end

  it 'SAD: should return 404 for non-existent account' do
    alice = create_account('alice', 'alice@example.com', 'password123')
    get 'api/v1/accounts/non_existent', nil, auth_request_header(alice)
    _(last_response.status).must_equal 404
  end
end
