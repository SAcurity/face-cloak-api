# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:face_records) do
      String :id, primary_key: true
      foreign_key :image_id, :images, type: String, null: false
      String :assigned_user_id
      String :assigned_at
      String :responded_at
      String :cloak_type, default: 'blur'

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
