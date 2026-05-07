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
    end
  end
end
