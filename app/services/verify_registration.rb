# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'erb'
require 'rest-client'

module FaceCloak
  # Sends a verification email for prospective account registration.
  class VerifyRegistration
    TEMPLATE_PATH = File.expand_path('../views/emails/registration_verification.html.erb', __dir__)

    class InvalidRegistration < StandardError; end
    class EmailProviderError < StandardError; end

    def initialize(registration)
      @registration = registration
    end

    def call
      validate_registration
      send_email
      @registration
    end

    private

    def validate_registration
      raise InvalidRegistration, 'Email is required' if @registration[:email].to_s.empty?
      raise InvalidRegistration, 'Verification URL is required' if @registration[:verification_url].to_s.empty?
      raise InvalidRegistration, 'Email already registered' unless email_available?
    end

    def email_available?
      Account.first(email_hash: SecureDB.hash(@registration[:email])).nil?
    end

    def send_email
      response = RestClient.post(mail_url, mail_form_data, mail_headers)
      verify_provider_response(response)
    rescue RestClient::ExceptionWithResponse => e
      log_provider_error(e.response)
      raise EmailProviderError, 'Email provider rejected the request'
    rescue KeyError, RestClient::Exception, SocketError, Timeout::Error, SystemCallError => e
      Api.logger.error("Registration email failed: #{e.message}")
      raise EmailProviderError, 'Email provider request failed'
    end

    def verify_provider_response(response)
      return if response.code.to_i < 300

      log_provider_error(response)
      raise EmailProviderError, 'Email provider rejected the request'
    end

    def log_provider_error(response)
      Api.logger.error("Mailgun error #{response&.code}: #{response&.body}")
    end

    def api_key = ENV.fetch('MAILGUN_API_KEY')
    def mail_url = "#{mailgun_api_base_url}/v3/#{mailgun_domain}/messages"
    def mailgun_api_base_url = ENV.fetch('MAILGUN_API_BASE_URL', 'https://api.mailgun.net').delete_suffix('/')
    def mailgun_domain = ENV.fetch('MAILGUN_DOMAIN')
    def from_email = ENV.fetch('MAILGUN_FROM_EMAIL', "postmaster@#{mailgun_domain}")
    def from_name = ENV.fetch('MAILGUN_FROM_NAME', 'FaceCloak')

    def mail_headers
      { Authorization: "Basic #{Base64.strict_encode64("api:#{api_key}")}" }
    end

    def mail_form_data
      {
        'from' => "#{from_name} <#{from_email}>",
        'to' => @registration[:email],
        'subject' => 'Activate your FaceCloak account',
        'html' => html_body
      }
    end

    def html_body
      ERB.new(File.read(TEMPLATE_PATH)).result_with_hash(
        verification_url: safe_verification_url
      )
    end

    def safe_verification_url
      CGI.escapeHTML(@registration[:verification_url].to_s)
    end
  end
end
