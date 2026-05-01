# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:action_logs) do
      primary_key :id # Logs can stay as sequence for performance, or UUID for consistency. Let's use serial.
      foreign_key :face_record_id, :face_records, type: :uuid, null: false
      Integer :actor_id, null: false # FK to accounts.id
      String :action, null: false

      DateTime :created_at
    end
  end
end
