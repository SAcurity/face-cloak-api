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

    post 'api/v1/accounts', signed_json(account_data), @req_header
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
    _(result['data'].first).must_include 'email'
    _(result['data'].first).must_include 'created_at'
  end

  it 'SAD: should require authentication to get list of all accounts' do
    create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts', nil, @req_header
    _(last_response.status).must_equal 401
  end

  it 'HAPPY: should list usernames for assignment without exposing account details' do
    alice = create_account('alice', 'alice@example.com', 'password123')
    create_account('bob', 'bob@example.com', 'password123')

    get 'api/v1/accounts/usernames', nil, auth_request_header(alice)
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data']).must_equal [
      { 'id' => alice.id, 'username' => 'alice' },
      { 'id' => FaceCloak::Account.first(username: 'bob').id, 'username' => 'bob' }
    ]
    _(result['data'].first).wont_include 'email'
  end

  it 'SAD: should not be able to create an account with existing username' do
    create_account('alice', 'alice@example.com', 'password123')
    account_data = { username: 'alice', email: 'alice2@example.com', password: 'password123' }

    post 'api/v1/accounts', signed_json(account_data), @req_header
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'already exists'
  end

  it 'SAD: should not be able to create an account with existing email' do
    create_account('alice', 'alice@example.com', 'password123')
    account_data = { username: 'alice2', email: 'alice@example.com', password: 'password123' }

    post 'api/v1/accounts', signed_json(account_data), @req_header
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'already exists'
  end

  it 'HAPPY: should be able to get account details' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts/alice', nil, auth_request_header(alice)
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data']['type']).must_equal 'authorized_account'
    account = result['data']['attributes']['account']
    _(account['type']).must_equal 'account'
    _(account['attributes']['username']).must_equal 'alice'
    _(account['attributes']['email']).must_equal 'alice@example.com'
    _(account).must_include 'policies'

    token = result['data']['attributes']['auth_token']
    _(FaceCloak::AuthToken.load(token).scope.to_s).must_equal FaceCloak::AuthScope::READ_ONLY
  end

  it 'HAPPY: read-only token can read account details' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    get 'api/v1/accounts/alice', nil,
        auth_header_with_scope(alice, FaceCloak::AuthScope::READ_ONLY).merge('CONTENT_TYPE' => 'application/json')

    _(last_response.status).must_equal 200
  end

  it 'HAPPY: should be able to search for account by email' do
    create_account('alice', 'alice@example.com', 'password123')
    search_data = { email: 'alice@example.com' }

    post 'api/v1/accounts/search', signed_json(search_data), @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['type']).must_equal 'account'
    _(result['attributes']['username']).must_equal 'alice'
  end

  it 'SAD: should return 404 for search with unknown email' do
    post 'api/v1/accounts/search', signed_json({ email: 'unknown@example.com' }), @req_header
    _(last_response.status).must_equal 404
  end

  it 'SECURITY: should reject unsigned account creation requests' do
    account_data = { username: 'alice', email: 'alice@example.com', password: 'password123' }

    post 'api/v1/accounts', account_data.to_json, @req_header

    _(last_response.status).must_equal 403
    _(JSON.parse(last_response.body)['message']).must_equal 'Must sign request'
  end

  it 'SECURITY: should reject unsigned account search requests' do
    create_account('alice', 'alice@example.com', 'password123')

    post 'api/v1/accounts/search', { email: 'alice@example.com' }.to_json, @req_header

    _(last_response.status).must_equal 403
  end

  it 'SAD: should return 404 for non-existent account' do
    alice = create_account('alice', 'alice@example.com', 'password123')
    get 'api/v1/accounts/non_existent', nil, auth_request_header(alice)
    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should let a user update their username' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    put 'api/v1/accounts/alice', { username: 'alice_new' }.to_json, auth_request_header(alice)

    _(last_response.status).must_equal 200
    result = JSON.parse(last_response.body)
    _(result['data']['attributes']['username']).must_equal 'alice_new'
    _(FaceCloak::Account.first(username: 'alice_new')).wont_be_nil
  end

  it 'HAPPY: should let an admin update another account identity' do
    admin = grant_admin(create_account('admin', 'admin@example.com', 'password123'))
    bob = create_account('bob', 'bob@example.com', 'password123')

    put 'api/v1/accounts/bob', { identity: 'admin' }.to_json, auth_request_header(admin)

    _(last_response.status).must_equal 200
    _(bob.refresh.system_roles.map(&:name)).must_include 'admin'
  end

  it 'HAPPY: should accept identity update payloads with string keys' do
    admin = grant_admin(create_account('admin', 'admin@example.com', 'password123'))
    bob = create_account('bob', 'bob@example.com', 'password123')

    FaceCloak::UpdateAccount.call(
      viewer: admin,
      target: bob,
      update_data: { 'identity' => 'admin' },
      auth_scope: FaceCloak::AuthScope.new
    )

    _(bob.refresh.system_roles.map(&:name)).must_include 'admin'
  end

  it 'SECURITY: should not let an admin change their own identity' do
    admin = grant_admin(create_account('admin', 'admin@example.com', 'password123'))

    put 'api/v1/accounts/admin', { identity: 'member' }.to_json, auth_request_header(admin)

    _(last_response.status).must_equal 403
    _(admin.refresh.system_roles.map(&:name)).must_include 'admin'
  end

  it 'HAPPY: should let a user change their password with current password' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    put 'api/v1/accounts/alice',
        { current_password: 'password123', new_password: 'new-password' }.to_json,
        auth_request_header(alice)

    _(last_response.status).must_equal 200
    _(FaceCloak::Account.first(username: 'alice').password?('new-password')).must_equal true
  end

  it 'SAD: should reject password change with wrong current password' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    put 'api/v1/accounts/alice',
        { current_password: 'wrong', new_password: 'new-password' }.to_json,
        auth_request_header(alice)

    _(last_response.status).must_equal 403
    _(FaceCloak::Account.first(username: 'alice').password?('password123')).must_equal true
  end

  it 'SECURITY: should reject account updates with a read-only token' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    put 'api/v1/accounts/alice',
        { username: 'alice_new' }.to_json,
        auth_header_with_scope(alice, FaceCloak::AuthScope::READ_ONLY).merge('CONTENT_TYPE' => 'application/json')

    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should let an admin see all accounts' do
    admin = grant_admin(create_account('admin', 'admin@example.com', 'password123'))
    create_account('bob', 'bob@example.com', 'password123')

    get 'api/v1/accounts', nil, auth_request_header(admin)

    _(last_response.status).must_equal 200
    usernames = JSON.parse(last_response.body)['data'].map { |account| account['username'] }
    _(usernames).must_include 'admin'
    _(usernames).must_include 'bob'
    _(JSON.parse(last_response.body)['data'].first).must_include 'last_active_at'
  end

  it 'HAPPY: should let an admin delete another user' do
    admin = grant_admin(create_account('admin', 'admin@example.com', 'password123'))
    bob = create_account('bob', 'bob@example.com', 'password123')

    delete 'api/v1/accounts/bob', nil, auth_request_header(admin)

    _(last_response.status).must_equal 200
    _(FaceCloak::Account[bob.id]).must_be_nil
  end

  it 'SAD: should not let a normal user delete another user' do
    alice = create_account('alice', 'alice@example.com', 'password123')
    bob = create_account('bob', 'bob@example.com', 'password123')

    delete 'api/v1/accounts/bob', nil, auth_request_header(alice)

    _(last_response.status).must_equal 403
    _(FaceCloak::Account[bob.id]).wont_be_nil
  end

  it 'HAPPY: should let a user delete themselves' do
    alice = create_account('alice', 'alice@example.com', 'password123')

    delete 'api/v1/accounts/alice', nil, auth_request_header(alice)

    _(last_response.status).must_equal 200
    _(FaceCloak::Account[alice.id]).must_be_nil
  end
end
