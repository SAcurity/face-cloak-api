# frozen_string_literal: true

require 'fileutils'
require 'yaml'

require_relative '../../app/models/face_record'

seed_path = File.expand_path('face_record_seeds.yml', __dir__)
seed_data = YAML.load_file(seed_path)

FileUtils.rm_rf(FaceCloak::FaceRecord::STORE_PATH)
FaceCloak::FaceRecord.setup

seed_data.each do |attributes|
  FaceCloak::FaceRecord.create(attributes)
end

puts "Loaded #{seed_data.size} face records into #{FaceCloak::FaceRecord::STORE_PATH}"
