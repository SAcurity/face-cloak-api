# frozen_string_literal: true

require 'json'
require 'jwt'
require 'securerandom'

module FaceCloak
  # Verifies a Google OIDC id_token and returns the standard auth envelope.
  class AuthenticateSsoAccount
    PROVIDER_GOOGLE = 'google'
    DEFAULT_GOOGLE_ISSUERS = %w[https://accounts.google.com accounts.google.com].freeze

    class BadRequestError < StandardError; end
    class UnauthorizedError < StandardError; end
    class UnsupportedProviderError < BadRequestError; end

    def self.call(sso_data)
      provider = sso_data[:provider].to_s
      raise UnsupportedProviderError, 'Unsupported SSO provider' unless provider == PROVIDER_GOOGLE

      claims = verified_claims(sso_data)
      account = find_or_create_account(provider, claims)

      auth_response(account)
    end

    def self.verified_claims(sso_data)
      verify_google_id_token(
        id_token: required(sso_data, :id_token),
        jwks: required(sso_data, :jwks)
      )
    end

    def self.auth_response(account)
      account_envelope = JSON.parse(account.to_json)
      account_envelope['capabilities'] = AccountPolicy.new(account).capabilities
      {
        type: 'authenticated_account',
        attributes: {
          account: account_envelope,
          auth_token: AuthenticateAccount.token_for(account_envelope, account.id)
        }
      }
    end

    def self.verify_google_id_token(id_token:, jwks:)
      header = JWT.decode(id_token, nil, false).last
      jwk_data = matching_jwk(jwks, header['kid'])
      raise UnauthorizedError, 'No matching JWKS key' unless jwk_data

      key = JWT::JWK.import(symbolize_keys(jwk_data)).public_key
      claims = JWT.decode(id_token, key, true, jwt_options).first
      validate_claims!(claims)
      claims
    rescue JWT::DecodeError, JWT::JWKError => e
      raise UnauthorizedError, e.message
    end

    def self.matching_jwk(jwks, kid)
      Array(jwks[:keys] || jwks['keys']).find { |key| key[:kid] == kid || key['kid'] == kid }
    end

    def self.jwt_options
      {
        algorithm: 'RS256',
        aud: Api.config.GOOGLE_CLIENT_ID,
        verify_aud: true,
        iss: google_issuers,
        verify_iss: true
      }
    end

    def self.validate_claims!(claims)
      raise UnauthorizedError, 'Missing subject' if claims['sub'].to_s.empty?
      raise UnauthorizedError, 'Missing email' if claims['email'].to_s.empty?
      raise UnauthorizedError, 'Email is not verified' unless claims['email_verified'] == true
    end

    def self.find_or_create_account(provider, claims)
      account = Account.first(sso_provider: provider, sso_subject: claims['sub'])
      return account if account

      account = Account.first(email_hash: SecureDB.hash(claims['email']))
      return link_account(account, provider, claims) if account

      create_sso_account(provider, claims)
    rescue Sequel::UniqueConstraintViolation => e
      raise BadRequestError, e.message
    end

    def self.link_account(account, provider, claims)
      account.update(sso_provider: provider, sso_subject: claims['sub'], avatar: claims['picture'])
      account
    end

    def self.create_sso_account(provider, claims)
      Account.create(
        username: unique_username(claims['email'], claims['sub']),
        email: claims['email'],
        avatar: claims['picture'],
        sso_provider: provider,
        sso_subject: claims['sub']
      )
    end

    def self.unique_username(email, subject)
      base = email.split('@').first.gsub(/[^a-zA-Z0-9_]/, '_')
      return base unless Account.first(username: base)

      suffix = subject.to_s[-8..] || SecureRandom.hex(4)
      "#{base}_#{suffix}"
    end

    def self.google_issuers
      configured = Api.config.GOOGLE_ISSUERS
      return DEFAULT_GOOGLE_ISSUERS if configured.to_s.empty?

      configured.split(',').map(&:strip).reject(&:empty?)
    end

    def self.required(data, key)
      value = data[key] || data[key.to_s]
      raise BadRequestError, "#{key} is required" if value.nil? || value == ''

      value
    end

    def self.symbolize_keys(hash)
      hash.to_h.transform_keys(&:to_sym)
    end
  end
end
