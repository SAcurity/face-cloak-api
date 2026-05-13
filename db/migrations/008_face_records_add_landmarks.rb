# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    add_column :face_records, :landmarks, String # Store as JSON string
  end
end
