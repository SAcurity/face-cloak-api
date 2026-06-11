# frozen_string_literal: true

require 'json'

module FaceCloak
  # Authorizes account detail access and mints a reduced-scope API key.
  class AuthorizeAccount
    # Raised when the requester may not view the target account.
    class ForbiddenError < StandardError
      def message
        'You are not allowed to access that account'
      end
    end

    def self.call(auth:, username:, issued_scope: AuthScope::READ_ONLY)
      viewer = requester_for(auth)
      target = Account.first(username:)
      raise Sequel::NoMatchingRow, 'Account not found' unless target

      policy = AccountPolicy.new(viewer, target, auth_scope: auth.scope)
      raise ForbiddenError unless policy.can_view?

      AuthorizedAccount.new(envelope_for(target, policy, viewer), issued_scope, account_id: target.id)
    end

    def self.requester_for(auth)
      account_id = auth&.account&.dig('attributes', 'id')
      account_id && Account.first(id: account_id)
    end

    def self.envelope_for(account, policy, viewer)
      envelope = account.to_h
      envelope[:policies] = policy.summary
      envelope[:capabilities] = policy.capabilities if viewer && viewer.id == account.id
      JSON.parse(envelope.to_json)
    end
  end
end
