# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'json'
require 'rbnacl'
require 'time'

require_relative 'cloak_type'

module FaceCloak
  # Represents one detected face and its masking lifecycle.
  class FaceRecord
    STORE_PATH = 'db/local/face_records'

    attr_reader :id, :image_id, :assigned_user_id, :assigned_at, :responded_at,
                :cloak_type, :updated_at

    def initialize(attributes)
      @id = attributes['id'] || new_id
      @image_id = attributes['image_id']
      @assigned_user_id = attributes['assigned_user_id']
      @assigned_at = attributes['assigned_at']
      @responded_at = attributes['responded_at']
      @cloak_type = normalize_cloak_type(attributes['cloak_type'])
      @updated_at = attributes['updated_at']
    end

    def assign_to(user_id, at: self.class.timestamp)
      @assigned_user_id = user_id
      @assigned_at = at
      @updated_at = nil
      self
    end

    def respond_with(cloak_type, at: self.class.timestamp)
      @responded_at ||= at
      @cloak_type = normalize_cloak_type(cloak_type)
      @updated_at = at
      self
    end

    def effective_cloak_type
      responded_at.nil? ? CloakType::DEFAULT : cloak_type
    end

    def to_h
      {
        type: 'face_record',
        id: id,
        image_id: image_id,
        assigned_user_id: assigned_user_id,
        assigned_at: assigned_at,
        responded_at: responded_at,
        cloak_type: cloak_type,
        updated_at: updated_at
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end

    def save
      FileUtils.mkdir_p(STORE_PATH)
      File.write("#{STORE_PATH}/#{id}.txt", to_json)
    end

    # file store must be setup once when application runs
    def self.setup
      FileUtils.mkdir_p(STORE_PATH)
    end

    def self.all
      Dir.glob("#{STORE_PATH}/*.txt").map do |file_path|
        record_file = File.read(file_path)
        new(JSON.parse(record_file))
      end
    end

    def self.create(attributes = {})
      face_record = new(attributes)
      face_record.save
      face_record
    end

    def self.find(find_id)
      record_file = File.read("#{STORE_PATH}/#{find_id}.txt")
      new(JSON.parse(record_file))
    rescue Errno::ENOENT
      nil
    end

    def self.timestamp
      # use taiwan time
      Time.now.getlocal('+08:00').iso8601
    end

    private

    def normalize_cloak_type(cloak_type)
      return CloakType::DEFAULT if cloak_type.nil?

      CloakType.normalize(cloak_type)
    end

    def new_id
      seed = "#{Time.now.to_f}-#{rand}"
      Base64.urlsafe_encode64(RbNaCl::Hash.sha256(seed))[0..9]
    end
  end
end
