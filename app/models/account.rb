# frozen_string_literal: true

require 'sequel'
require 'json'
require_relative 'password'

module FaceCloak
  # Models a registered account
  class Account < Sequel::Model
    one_to_many :owned_images, class: :'FaceCloak::Image', key: :owner_id
    one_to_many :face_assignments, class: :'FaceCloak::FaceRecord', key: :assigned_user_id

    many_to_many :system_roles,
                 class: :'FaceCloak::Role',
                 join_table: :accounts_roles,
                 left_key: :account_id,
                 right_key: :role_id

    many_to_many :assigned_images,
                 class: :'FaceCloak::Image',
                 join_table: :accounts_images,
                 left_key: :account_id,
                 right_key: :image_id

    plugin :association_dependencies, assigned_images: :nullify

    plugin :whitelist_security
    set_allowed_columns :username, :email, :password

    plugin :timestamps, update_on_create: true

    # Email is PII: store encrypted ciphertext + HMAC lookup hash.
    def email
      SecureDB.decrypt(email_secure)
    end

    def email=(plaintext)
      self.email_secure = SecureDB.encrypt(plaintext)
      self.email_hash   = SecureDB.hash(plaintext)
    end

    def password=(new_password)
      self.password_digest = Password.digest(new_password).to_s
    end

    def password?(try_password)
      digest = Password.from_digest(password_digest)
      digest.correct?(try_password)
    end

    def admin?
      system_roles.any? { |r| r.name == 'admin' }
    end

    # rubocop:disable Metrics/MethodLength
    def to_h
      {
        type: 'account',
        attributes: {
          id:,
          username:,
          email:
        },
        include: {
          system_roles: system_roles.map(&:name),
          face_assignments: face_assignments.map do |e|
            { face_id: e.id, image_id: e.image_id, image_name: e.image.file_name, cloak_type: e.cloak_type }
          end
        }
      }
    end
    # rubocop:enable Metrics/MethodLength

    def to_json(options = {})
      JSON(to_h, options)
    end
  end
end
