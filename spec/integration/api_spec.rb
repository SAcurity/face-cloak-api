# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceCloak Web API' do
  include Rack::Test::Methods

  describe 'Root route' do
    it 'should find the root route' do
      get '/'
      _(last_response.status).must_equal 200
    end

    it 'SECURITY: sends browser security headers' do
      get '/'

      _(last_response.headers['X-Content-Type-Options']).must_equal 'nosniff'
      _(last_response.headers['X-Frame-Options']).must_equal 'DENY'
      _(last_response.headers['Referrer-Policy']).must_equal 'no-referrer'
      _(last_response.headers['Content-Security-Policy']).must_include "default-src 'none'"
      _(last_response.headers['Content-Security-Policy']).must_include '/api/v1/security/csp-report'
    end
  end

  describe 'CSP report route' do
    it 'SECURITY: accepts browser CSP reports without signed request' do
      report = {
        'csp-report' => {
          'blocked-uri' => 'https://cdn.example/script.js',
          'violated-directive' => 'script-src',
          'document-uri' => 'https://app.example/account'
        }
      }

      post 'api/v1/security/csp-report', report.to_json, { 'CONTENT_TYPE' => 'application/csp-report' }

      _(last_response.status).must_equal 204
    end

    it 'BAD: rejects malformed CSP reports' do
      post 'api/v1/security/csp-report', '{bad-json', { 'CONTENT_TYPE' => 'application/csp-report' }

      _(last_response.status).must_equal 400
    end
  end
end
