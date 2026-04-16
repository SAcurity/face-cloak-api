# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:face_records) do
      primary_key :id
      foreign_key :image_id, :images, null: false
      String :assigned_user_id
      String :assigned_at
      String :responded_at
      String :cloak_type, default: 'blur'

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
