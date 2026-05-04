# frozen_string_literal: true

require 'fileutils'
require 'base64'
require 'securerandom'

module FaceCloak
  # Service object to handle physical storage and naming of image files
  class StoreImageFile
    STORAGE_DIR = 'db/local/storage'

    def self.call(owner_id:, file_name:, file_data:)
      FileUtils.mkdir_p(STORAGE_DIR)

      # 1. Handle naming and deduplication
      final_name = ensure_unique_name(owner_id, file_name)

      # 2. Persist to disk
      storage_key = "#{SecureRandom.hex(16)}#{File.extname(final_name)}"
      raw_data = decode_data(file_data)
      File.binwrite(File.join(STORAGE_DIR, storage_key), raw_data)

      { file_name: final_name, storage_key: }
    end

    def self.decode_data(data)
      if File.file?(data)
        File.binread(data)
      else
        Base64.strict_decode64(data.gsub(/\s+/, ''))
      end
    rescue ArgumentError
      raise 'file_data must be a Base64 payload or a readable file path'
    end

    def self.ensure_unique_name(owner_id, file_name)
      ext = File.extname(file_name)
      stem = File.basename(file_name, ext)
      suffix = 1
      candidate = file_name

      while Image.first(owner_id:, file_name: candidate)
        candidate = "#{stem}-#{suffix}#{ext}"
        suffix += 1
      end
      candidate
    end
  end
end
