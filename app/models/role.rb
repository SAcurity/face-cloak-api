# frozen_string_literal: true

require 'sequel'

module FaceCloak
  # Models a system role
  class Role < Sequel::Model
    many_to_many :accounts,
                 class: :'FaceCloak::Account',
                 join_table: :accounts_roles,
                 left_key: :role_id,
                 right_key: :account_id

    plugin :whitelist_security
    set_allowed_columns :name
  end
end
