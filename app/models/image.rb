# frozen_string_literal: true

require 'json'
require 'sequel'
require 'base64'
require 'fileutils'
require 'securerandom'

module FaceCloak
  # Represents an image that can contain multiple face records.
  class Image < Sequel::Model
    STORAGE_DIR = 'db/local/storage'

    one_to_many :face_records
    plugin :association_dependencies, face_records: :destroy

    plugin :timestamps

    def before_create
      persist_incoming_file_data!
      super
    end

    def before_update
      persist_incoming_file_data! if changed_columns.include?(:file_data)
      super
    end

    def before_destroy
      delete_stored_file!
      super
    end

    # Generates a secure random filename and saves binary data
    def save_file(raw_data)
      storage_key = persist_raw_file(raw_data)
      return self.file_data = storage_key if new?

      update(file_data: storage_key)
    end

    def read_file
      raise 'Stored image file is missing' unless File.exist?(storage_path)

      File.binread(storage_path)
    end

    def to_h
      {
        type: 'image',
        attributes: {
          id:,
          owner_id:,
          file_name:,
          file_data:
        }
      }
    end

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end

    private

    def persist_incoming_file_data!
      return if file_data.nil? || file_data.empty? || stored_file_key?(file_data)

      raw_data = if File.file?(file_data)
                   File.binread(file_data)
                 else
                   Base64.strict_decode64(file_data.gsub(/\s+/, ''))
                 end
      self.file_data = persist_raw_file(raw_data)
    end

    def persist_raw_file(raw_data)
      FileUtils.mkdir_p(STORAGE_DIR)

      storage_key = "#{SecureRandom.hex(16)}#{File.extname(file_name)}"
      File.binwrite(File.join(STORAGE_DIR, storage_key), raw_data)
      storage_key
    rescue ArgumentError
      raise 'file_data must be a Base64 payload or a readable file path'
    end

    def storage_path
      File.join(STORAGE_DIR, file_data.to_s)
    end

    def stored_file_key?(candidate)
      return false if File.file?(candidate)

      File.exist?(File.join(STORAGE_DIR, candidate.to_s))
    end

    def delete_stored_file!
      return if file_data.nil? || file_data.empty?

      path = storage_path
      File.delete(path) if File.exist?(path)
    end
  end
end
