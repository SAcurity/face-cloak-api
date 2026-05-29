# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      begin
        auth_account_id = current_account_id
        viewer = Account.first(id: auth_account_id) if auth_account_id
      rescue AuthToken::InvalidTokenError
        routing.halt 401, { message: 'Invalid auth token' }.to_json
      rescue AuthToken::ExpiredTokenError
        routing.halt 401, { message: 'Expired auth token' }.to_json
      end

      routing.on 'search' do
        routing.post do
          search_data = HttpRequest.new(routing).body_data
          account = if search_data[:username]
                      Account.first(username: search_data[:username])
                    elsif search_data[:email]
                      Account.first(email_hash: SecureDB.hash(search_data[:email]))
                    end

          raise(Sequel::NoMatchingRow, 'Account not found') unless account
          account.to_json
        end
      end

      routing.on String do |username|
        routing.get do
          require_authenticated_account(routing)
          account = Account.first(username:)
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          policy = AccountPolicy.new(viewer, account)
          routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_view?

          output = account.to_h
          output[:policies] = policy.summary
          JSON.pretty_generate(output)
        end
      end

      routing.is do
        routing.get do
          require_authenticated_account(routing)

          viewable_accounts = AccountPolicy::AccountScope.new(viewer).viewable
          accounts_data = viewable_accounts.map do |account|
            policy = AccountPolicy.new(viewer, account)
            {
              id: account.id,
              username: account.username,
              policies: policy.index_summary
            }
          end

          JSON.pretty_generate(
            data: accounts_data,
            capabilities: AccountPolicy.new(viewer).capabilities
          )
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
