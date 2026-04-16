# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:action_logs) do
      primary_key :id
      foreign_key :face_record_id, :face_records, null: false
      String :actor_id, null: false
      String :action, null: false # e.g., 'create', 'assign', 'unassign', 'respond'

      DateTime :created_at
    end
  end
end
