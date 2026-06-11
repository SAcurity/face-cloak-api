# frozen_string_literal: true

require 'json'
require 'roda'
require_relative 'app'

module FaceCloak
  # Browser-facing security headers and report collection.
  class Api < Roda
    CONTENT_SECURITY_POLICY = [
      "default-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'none'",
      "form-action 'none'",
      'report-uri /api/v1/security/csp-report'
    ].join('; ').freeze

    def apply_security_headers
      response['X-Content-Type-Options'] = 'nosniff'
      response['X-Frame-Options'] = 'DENY'
      response['Referrer-Policy'] = 'no-referrer'
      response['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=(), payment=()'
      response['Content-Security-Policy'] = CONTENT_SECURITY_POLICY
      response['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains' if Api.environment == :production
    end

    route('security') do |routing|
      routing.is 'csp-report' do
        routing.post do
          report = parse_csp_report(routing)
          Api.logger.warn("CSP VIOLATION: #{summarize_csp_report(report)}")

          response.status = 204
          ''
        rescue JSON::ParserError
          routing.halt 400, { message: 'Malformed CSP report' }.to_json
        end
      end
    end

    private

    def parse_csp_report(routing)
      raw = routing.body.read
      return {} if raw.to_s.empty?

      JSON.parse(raw)
    end

    def summarize_csp_report(report)
      body = csp_report_body(report)
      fields = {
        'blocked-uri' => body['blocked-uri'],
        'violated-directive' => body['violated-directive'],
        'document-uri' => body['document-uri'],
        'source-file' => body['source-file']
      }.compact

      fields.to_json
    end

    def csp_report_body(report)
      return report['csp-report'] || report if report.is_a?(Hash)
      return report.first['body'] || report.first if report.is_a?(Array) && report.first.is_a?(Hash)

      {}
    end
  end
end
