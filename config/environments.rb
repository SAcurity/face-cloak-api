# frozen_string_literal: true

require 'roda'
require 'figaro'
require 'logger'
require 'sequel'
require './app/lib/secure_db'
require './app/lib/gemini_api'

module FaceCloak
  # Configuration for the API
  class Api < Roda
    plugin :environments

    # load config secrets into local environment variables (ENV)
    Figaro.application = Figaro::Application.new(
      environment: environment,
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load

    # Make the environment variables accessible to other classes
    def self.config = Figaro.env

    # Connect and make the database accessible to other classes
    db_url = ENV.delete('DATABASE_URL')
    DB = Sequel.connect("#{db_url}?encoding=utf8")
    def self.DB = DB # rubocop:disable Naming/MethodName

    # Setup logger
    LOGGER = Logger.new($stderr)
    def self.logger = LOGGER

    # Setup SecureDB
    db_key = ENV.delete('DB_KEY')
    hash_key = ENV.delete('HASH_KEY')
    SecureDB.setup(db_key, hash_key)

    # Setup GeminiApi
    gemini_key = ENV.delete('GEMINI_API_KEY')
    use_gemini = gemini_key && (environment != :test || ENV.fetch('USE_REAL_GEMINI_IN_TEST', nil) == 'true')
    GeminiApi.setup(gemini_key) if use_gemini

    configure :development, :production do
      plugin :common_logger, $stderr
    end

    configure :development, :test do
      require 'pry'
    end
  end
end
