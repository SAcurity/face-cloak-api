# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/minitest'

describe 'Test VerifyRegistration service' do
  before do
    wipe_database
    setup_mailgun_env
    base_url = ENV.fetch('MAILGUN_API_BASE_URL').delete_suffix('/')
    @mail_url = "#{base_url}/v3/#{ENV.fetch('MAILGUN_DOMAIN')}/messages"
    @registration = {
      email: 'newperson@example.com',
      verification_url: 'https://app.example.com/auth/register/some-token'
    }
  end

  after { WebMock.reset! }

  it 'HAPPY: POSTs the Mailgun form and returns the registration' do
    stub = stub_request(:post, @mail_url)
           .with(headers: { 'Authorization' => /^Basic .+/ })
           .to_return(status: 200, body: { id: 'fake-email-id' }.to_json)

    result = FaceCloak::VerifyRegistration.new(@registration).call

    _(result[:email]).must_equal @registration[:email]
    assert_requested(stub)
  end

  it 'SECURITY: request body includes from/to/subject/html' do
    stub_request(:post, @mail_url).to_return(status: 200)

    FaceCloak::VerifyRegistration.new(@registration).call

    assert_requested(:post, @mail_url) do |req|
      body = URI.decode_www_form(req.body).to_h

      body['from'].include?(ENV.fetch('MAILGUN_FROM_EMAIL', "postmaster@#{ENV.fetch('MAILGUN_DOMAIN')}")) &&
        body['to'] == @registration[:email] &&
        body['subject'].include?('Activate your FaceCloak account') &&
        !body['html'].include?('Activate your FaceCloak account') &&
        body['html'].include?('Sign up for FaceCloak') &&
        body['html'].include?('Thanks for joining FaceCloak!') &&
        body['html'].include?('Activate your account to continue') &&
        body['html'].include?('Activate Account') &&
        body['html'].include?('This link expires in 30 minutes') &&
        body['html'].include?(@registration[:verification_url])
    end
  end

  it 'SAD: raises InvalidRegistration when email already registered' do
    create_account('alice', @registration[:email], 'password123')

    _ { FaceCloak::VerifyRegistration.new(@registration).call }
      .must_raise FaceCloak::VerifyRegistration::InvalidRegistration
  end

  it 'SAD: raises EmailProviderError on provider failure' do
    stub_request(:post, @mail_url).to_return(status: 503, body: 'unavailable')

    _ { FaceCloak::VerifyRegistration.new(@registration).call }
      .must_raise FaceCloak::VerifyRegistration::EmailProviderError
  end
end
