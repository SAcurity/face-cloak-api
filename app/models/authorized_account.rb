# frozen_string_literal: true

require 'json'

module FaceCloak
  # Account envelope paired with an AuthScope for token minting/reconstruction.
  class AuthorizedAccount
    attr_reader :account, :scope

    def initialize(account, auth_scope = AuthScope.new, account_id: nil)
      @account = account
      @account_id = account_id
      @scope =
        case auth_scope
        when AuthScope then auth_scope
        else AuthScope.new(auth_scope)
        end
    end

    def token
      @token ||= AuthToken.new(token_payload, scope: @scope).to_s
    end

    def to_h
      {
        type: 'authorized_account',
        attributes: { account: @account, auth_token: token }
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end

    private

    def token_payload
      attrs = @account['attributes'] || {}
      {
        'type' => 'account',
        'attributes' => {
          'id' => @account_id || attrs['id'],
          'username' => attrs['username']
        }
      }
    end
  end
end
