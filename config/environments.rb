# frozen_string_literal: true

require 'roda'
require 'figaro'
require 'logger'
require 'sequel'
require './app/lib/secure_db'
require './app/lib/auth_token'
require './app/lib/registration_token'
require './app/lib/gemini_api'
require './app/lib/image_storage'

module FaceCloak
  # Configuration for the API
  class Api < Roda
    class StartupConfigError < StandardError; end

    plugin :environments

    # load config secrets into local environment variables (ENV)
    Figaro.application = Figaro::Application.new(
      environment: environment,
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load

    # Make the environment variables accessible to other classes
    def self.config = Figaro.env

    required_env = lambda do |name|
      value = ENV.delete(name)
      raise StartupConfigError, "Missing required env var: #{name}" if value.to_s.empty?

      value
    end

    # Connect and make the database accessible to other classes
    db_url = required_env.call('DATABASE_URL')
    DB = Sequel.connect("#{db_url}?encoding=utf8")
    def self.DB = DB # rubocop:disable Naming/MethodName

    # Setup logger
    LOGGER = Logger.new($stderr)
    def self.logger = LOGGER

    # Setup SecureDB
    db_key = required_env.call('DB_KEY')
    hash_key = required_env.call('HASH_KEY')
    SecureDB.setup(db_key, hash_key)

    # Setup AuthToken and RegistrationToken
    msg_key = required_env.call('MSG_KEY')
    AuthToken.setup(msg_key)
    RegistrationToken.setup(msg_key)

    # Setup GeminiApi
    gemini_key = ENV.delete('GEMINI_API_KEY')
    use_gemini = gemini_key && (environment != :test || ENV.fetch('USE_REAL_GEMINI_IN_TEST', nil) == 'true')
    GeminiApi.setup(gemini_key) if use_gemini

    # Setup image storage
    storage_provider = ENV.delete('STORAGE_PROVIDER')
    storage_provider = environment == :production ? 's3' : 'local' if storage_provider.to_s.empty?
    ImageStorage.setup(
      provider: storage_provider,
      local_root: File.join(ImageStorage::LOCAL_ROOT, environment.to_s),
      bucket: ENV.delete('S3_BUCKET_NAME'),
      region: ENV.delete('AWS_REGION'),
      access_key_id: ENV.delete('AWS_ACCESS_KEY_ID'),
      secret_access_key: ENV.delete('AWS_SECRET_ACCESS_KEY'),
      endpoint: ENV.delete('S3_ENDPOINT'),
      force_path_style: ENV.delete('S3_FORCE_PATH_STYLE') == 'true'
    )

    configure :development, :production do
      plugin :common_logger, $stderr
    end

    configure :development do
      require 'pry'
    end

    configure :production do
      plugin :redirect_http_to_https
      plugin :hsts
    end
  end
end
