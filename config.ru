# frozen_string_literal: true

require_relative 'app/controllers/app'

run FaceCloak::Api.freeze.app
