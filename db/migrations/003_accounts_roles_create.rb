# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_join_table(
      account_id: { table: :accounts, type: :integer },
      role_id: { table: :roles, type: :integer }
    )
  end
end
