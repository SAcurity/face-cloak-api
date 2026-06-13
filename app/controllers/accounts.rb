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

      routing.on 'usernames' do
        routing.get do
          require_authenticated_account(routing)

          accounts_data = Account.order(:username).map do |account|
            {
              id: account.id,
              username: account.username
            }
          end

          JSON.pretty_generate(data: accounts_data)
        end
      end

      routing.on 'search' do
        routing.post do
          search_data = HttpRequest.new(routing).signed_body_data
          username = search_data[:username]
          account = Account.first(username:) if username

          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          account.to_json
        rescue SignedRequest::VerificationError
          routing.halt 403, { message: 'Must sign request' }.to_json
        end
      end

      routing.on String do |username|
        routing.get do
          require_authenticated_account(routing)
          account = Account.first(username:)
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          authorized = AuthorizeAccount.call(auth: @auth, username:)
          { data: authorized }.to_json
        rescue AuthorizeAccount::ForbiddenError
          routing.halt 403, { message: 'Forbidden' }.to_json
        end

        routing.on method: :put do
          require_authenticated_account(routing)
          account = Account.first(username:)
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          update_data = HttpRequest.new(routing).body_data
          updated = UpdateAccount.call(
            viewer:, target: account, update_data:, auth_scope: current_auth_scope
          )
          { message: 'Account updated', data: updated.to_h }.to_json
        rescue UpdateAccount::ForbiddenError
          routing.halt 403, { message: 'Forbidden' }.to_json
        rescue UpdateAccount::InvalidPasswordError => e
          routing.halt 403, { message: e.message }.to_json
        rescue ArgumentError => e
          routing.halt 400, { message: e.message }.to_json
        end

        routing.on method: :delete do
          require_authenticated_account(routing)
          account = Account.first(username:)
          raise(Sequel::NoMatchingRow, 'Account not found') unless account

          DeleteAccount.call(viewer:, target: account, auth_scope: current_auth_scope)
          { message: 'Account deleted' }.to_json
        rescue DeleteAccount::ForbiddenError
          routing.halt 403, { message: 'Forbidden' }.to_json
        end
      end

      routing.is do
        routing.get do
          require_authenticated_account(routing)

          viewable_accounts = AccountPolicy::AccountScope.new(viewer, auth_scope: current_auth_scope).viewable
          accounts_data = viewable_accounts.map do |account|
            policy = AccountPolicy.new(viewer, account, auth_scope: current_auth_scope)
            {
              id: account.id,
              username: account.username,
              email: account.email,
              has_password: !account.password_digest.to_s.empty?,
              sso_provider: account.sso_provider,
              created_at: account.created_at,
              updated_at: account.updated_at,
              last_active_at: last_active_at(account),
              policies: policy.index_summary
            }
          end

          JSON.pretty_generate(
            data: accounts_data,
            capabilities: AccountPolicy.new(viewer, auth_scope: current_auth_scope).capabilities
          )
        end

        routing.post do
          account_data = HttpRequest.new(routing).signed_body_data
          new_account = CreateAccount.call(account_data:)
          response.status = 201
          response['Location'] = "#{@account_route}/#{new_account.username}"
          { message: 'Account created', data: new_account.to_h }.to_json
        rescue SignedRequest::VerificationError
          routing.halt 403, { message: 'Must sign request' }.to_json
        rescue StandardError => e
          Api.logger.warn "ACCOUNT CREATION ERROR: #{e.message}"
          routing.halt 400, { message: e.message }.to_json
        end
      end
    end

    def last_active_at(account)
      ActionLog.where(actor_id: account.id).max(:created_at) || account.updated_at
    end
  end
end
