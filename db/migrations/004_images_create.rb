# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:images) do
      uuid :id, primary_key: true
      foreign_key :owner_id, :accounts, on_delete: :cascade, null: false
      String :file_name, null: false
      String :file_data, null: false

      DateTime :created_at
      DateTime :updated_at

      unique [:owner_id, :file_name]
    end
  end
end
