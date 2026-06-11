# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:action_logs) do
      primary_key :id # stay as sequence for performance
      foreign_key :face_record_id, :face_records, type: :uuid, on_delete: :cascade, null: false
      foreign_key :actor_id, :accounts, on_delete: :cascade, null: false
      foreign_key :assigned_user_id, :accounts, on_delete: :set_null
      String :action, null: false
      String :cloak_type

      DateTime :created_at
    end
  end
end
