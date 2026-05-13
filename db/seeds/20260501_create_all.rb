# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'securerandom'

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
Sequel.seed(:development, :test) do
  def run
    puts 'Seeding roles, accounts, system roles, images, face records, assignments, and responses'
    create_roles
    create_accounts
    assign_system_roles
    create_images
    create_face_records
    create_assignments
    create_responses
  end
end

DIR = File.dirname(__FILE__)
ALL_ROLES = %w[admin member].freeze
ACCOUNTS_INFO     = YAML.load_file("#{DIR}/accounts_seed.yml")
IMAGES_INFO       = YAML.load_file("#{DIR}/image_seeds.yml")
FACE_RECORDS_INFO = YAML.load_file("#{DIR}/face_record_seeds.yml")
ASSIGNMENTS_INFO  = YAML.load_file("#{DIR}/assignments_seed.yml")
RESPONSES_INFO    = YAML.load_file("#{DIR}/responses_seed.yml")

SYSTEM_ROLE_ASSIGNMENTS = {
  'alice' => %w[admin member],
  'bob' => %w[member],
  'charlie' => %w[member],
  'diana' => %w[member]
}.freeze

def create_roles
  ALL_ROLES.each { |name| FaceCloak::Role.find_or_create(name:) }
end

def create_accounts
  ACCOUNTS_INFO.each do |account_info|
    next if FaceCloak::Account.first(username: account_info['username'])

    FaceCloak::CreateAccount.call(account_data: account_info)
  end
end

def assign_system_roles
  SYSTEM_ROLE_ASSIGNMENTS.each do |username, role_names|
    account = FaceCloak::Account.first(username:)
    next unless account

    role_names.each do |role_name|
      role = FaceCloak::Role.first(name: role_name)
      account.add_system_role(role)
    end
  end
end

def create_images
  FileUtils.mkdir_p(FaceCloak::Image::STORAGE_DIR)
  IMAGES_INFO.each do |img_info|
    owner = FaceCloak::Account.first(username: img_info['owner_username'])
    next unless owner
    next if FaceCloak::Image.first(owner_id: owner.id, file_name: img_info['file_name'])

    # Get absolute path for seed files
    src_path = File.join(DIR, 'files', File.basename(img_info['file_data']))

    # Logic: generate a unique storage name (UUID) just like the actual service
    storage_filename = "#{SecureRandom.uuid}.png"
    dest_path = File.join(FaceCloak::Image::STORAGE_DIR, storage_filename)

    # Use sips to ensure seed files are proper PNGs
    system("sips -s format png --deleteProperty orientation '#{src_path}' --out '#{dest_path}' > /dev/null 2>&1")
    FileUtils.cp(src_path, dest_path) unless File.exist?(dest_path)

    FaceCloak::Image.create(
      owner_id: owner.id,
      file_name: img_info['file_name'],
      file_data: storage_filename
    )
  end
end

def create_face_records
  FACE_RECORDS_INFO.each do |record|
    image = FaceCloak::Image.first(file_name: record['image_file_name'])
    next unless image

    FaceCloak::CreateFaceRecord.call(
      face_data: {
        image_id: image.id,
        x_min: record['x_min'],
        y_min: record['y_min'],
        x_max: record['x_max'],
        y_max: record['y_max']
      },
      actor_id: image.owner_id
    )
  end
end

def create_assignments
  ASSIGNMENTS_INFO.each do |assign_info|
    image = FaceCloak::Image.first(file_name: assign_info['image_file_name'])
    account = FaceCloak::Account.first(username: assign_info['assignee_username'])
    next unless image && account

    # Find the specific face by sorting coordinates (Left to Right)
    face = image.face_records_dataset.order(:x_min, :y_min).all[assign_info['face_index']]
    next unless face

    FaceCloak::AssignFaceRecord.call(
      face_record_id: face.id,
      assigned_user_id: account.id,
      actor_id: image.owner_id
    )
  end
end

def create_responses
  RESPONSES_INFO.each do |resp_info|
    image = FaceCloak::Image.first(file_name: resp_info['image_file_name'])
    account = FaceCloak::Account.first(username: resp_info['username'])
    next unless image && account

    # Find the face assigned to THIS user in THIS image
    face = FaceCloak::FaceRecord.first(image_id: image.id, assigned_user_id: account.id)
    next unless face

    FaceCloak::RespondToFaceRecord.call(
      face_record_id: face.id,
      cloak_type: resp_info['cloak_type'],
      actor_id: account.id,
      skip_render: true
    )
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
