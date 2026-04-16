# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:images) do
      String :id, primary_key: true
      String :owner_id, null: false
      String :file_name, null: false
      String :file_data, null: false # Stores the generated local storage key

      DateTime :created_at
    end

    add_index :images, %i[owner_id file_name], unique: true, concurrently: false
  end
end
