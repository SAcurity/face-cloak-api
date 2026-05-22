# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('auth') do |routing|
      routing.is 'authenticate' do
        # POST api/v1/auth/authenticate
        routing.post do
          credentials = HttpRequest.new(routing).body_data
          account = AuthenticateAccount.call(credentials)
          account.to_json
        rescue AuthenticateAccount::UnauthorizedError => e
          Api.logger.warn "AUTHENTICATION ERROR: #{e.message}"
          routing.halt 403, { message: 'Invalid credentials' }.to_json
        end
      end

      routing.is 'register' do
        # POST api/v1/auth/register
        routing.post do
          registration = HttpRequest.new(routing).body_data
          VerifyRegistration.new(registration).call
          response.status = 202
          { message: 'Verification email sent' }.to_json
        rescue VerifyRegistration::InvalidRegistration => e
          routing.halt 400, { message: e.message }.to_json
        rescue VerifyRegistration::EmailProviderError => e
          Api.logger.error("REGISTRATION EMAIL ERROR: #{e.message}")
          routing.halt 500, { message: 'Could not send verification email' }.to_json
        end
      end
    end
  end
end
