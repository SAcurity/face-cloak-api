# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    alter_table(:accounts) do
      add_column :sso_provider, String
      add_column :sso_subject, String
      add_column :avatar, String
      set_column_allow_null :password_digest
      # rubocop:disable Sequel/ConcurrentIndex
      add_index %i[sso_provider sso_subject], unique: true
      # rubocop:enable Sequel/ConcurrentIndex
    end
  end
end
