# frozen_string_literal: true

require 'digest'
require 'fileutils'

module FaceCloak
  # Stores original image bytes using either local disk or S3.
  class ImageStorage
    LOCAL_ROOT = 'db/local/storage'
    DOWNLOAD_CACHE_DIR = 'tmp/storage_cache'

    class << self
      def setup(options)
        @provider = options[:provider].to_s.empty? ? 'local' : options[:provider]
        @bucket = options[:bucket]
        @s3_client = build_s3_client(
          region: options[:region],
          access_key_id: options[:access_key_id],
          secret_access_key: options[:secret_access_key],
          endpoint: options[:endpoint],
          force_path_style: options[:force_path_style]
        )
      end

      def provider
        @provider || 'local'
      end

      def put_file(key, source_path, content_type: nil)
        if s3?
          File.open(source_path, 'rb') do |file|
            @s3_client.put_object(bucket: @bucket, key:, body: file, content_type:)
          end
        else
          destination = local_file_path(key)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(source_path, destination)
        end
      end

      def get(key)
        return File.binread(local_file_path(key)) unless s3?

        @s3_client.get_object(bucket: @bucket, key:).body.read
      end

      def delete(key)
        if s3?
          @s3_client.delete_object(bucket: @bucket, key:)
        else
          FileUtils.rm_f(local_file_path(key))
        end
      end

      def exist?(key)
        return File.exist?(local_file_path(key)) unless s3?

        @s3_client.head_object(bucket: @bucket, key:)
        true
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        false
      end

      def local_path(key)
        return local_file_path(key) unless s3?

        cached_path = cached_file_path(key)
        FileUtils.mkdir_p(File.dirname(cached_path))
        File.binwrite(cached_path, get(key)) unless File.exist?(cached_path)
        cached_path
      end

      private

      def s3?
        provider == 's3'
      end

      def local_file_path(key)
        File.join(LOCAL_ROOT, key.to_s)
      end

      def cached_file_path(key)
        extension = File.extname(key.to_s)
        filename = "#{Digest::SHA256.hexdigest(key.to_s)}#{extension}"
        File.join(DOWNLOAD_CACHE_DIR, filename)
      end

      def build_s3_client(region:, access_key_id:, secret_access_key:, endpoint:, force_path_style:)
        return nil unless provider == 's3'

        validate_s3_config!(bucket: @bucket, region:, access_key_id:, secret_access_key:)
        require 'aws-sdk-s3'
        Aws::S3::Client.new(
          region:,
          access_key_id:,
          secret_access_key:,
          endpoint: empty_to_nil(endpoint),
          force_path_style:
        )
      end

      def validate_s3_config!(bucket:, region:, access_key_id:, secret_access_key:)
        missing = []
        missing << 'S3_BUCKET_NAME' if bucket.to_s.empty?
        missing << 'AWS_REGION' if region.to_s.empty?
        missing << 'AWS_ACCESS_KEY_ID' if access_key_id.to_s.empty?
        missing << 'AWS_SECRET_ACCESS_KEY' if secret_access_key.to_s.empty?
        raise "Missing S3 storage config: #{missing.join(', ')}" unless missing.empty?
      end

      def empty_to_nil(value)
        value.to_s.empty? ? nil : value
      end
    end
  end
end
