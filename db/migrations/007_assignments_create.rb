# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_join_table(
      image_id: { table: :images, type: :uuid },
      assignee_id: { table: :accounts, type: :integer }
    )
  end
end
