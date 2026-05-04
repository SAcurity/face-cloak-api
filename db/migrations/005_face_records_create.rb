# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:face_records) do
      uuid :id, primary_key: true
      foreign_key :image_id, :images, type: :uuid, on_delete: :cascade, null: false
      foreign_key :assigned_user_id, :accounts, on_delete: :set_null
      DateTime :assigned_at
      DateTime :responded_at
      String :cloak_type, default: 'blur'

      DateTime :created_at
      DateTime :updated_at

      unique [:image_id, :assigned_user_id]
    end
  end
end
