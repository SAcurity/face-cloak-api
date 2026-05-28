# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on 'search' do
        routing.post do
          search_data = HttpRequest.new(routing).body_data
          email = search_data[:email]
          account = Account.first(email_hash: SecureDB.hash(email))
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          account.to_json
        end
      end

      routing.on String do |username|
        routing.get do
          account = Account.first(username:)
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          account.to_json
        end
      end

      routing.is do
        routing.get do
          require_authenticated_account(routing)
          accounts = Account.order(:username).all.map do |account|
            { id: account.id, username: account.username }
          end

          JSON.pretty_generate(data: accounts)
        end

        routing.post do
          account_data = HttpRequest.new(routing).body_data
          new_account = CreateAccount.call(account_data:)
          response.status = 201
          response['Location'] = "#{@account_route}/#{new_account.username}"
          { message: 'Account created', data: new_account.to_h }.to_json
        rescue StandardError => e
          Api.logger.warn "ACCOUNT CREATION ERROR: #{e.message}"
          routing.halt 400, { message: e.message }.to_json
        end
      end
    end
  end
end
