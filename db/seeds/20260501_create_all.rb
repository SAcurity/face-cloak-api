# frozen_string_literal: true

Sequel.seed(:development, :test) do
  def run
    puts 'Seeding roles and accounts'
    setup_roles
    setup_accounts
  end
end

def setup_roles
  %w[admin member].each do |role_name|
    FaceCloak::Role.find_or_create(name: role_name)
  end
end

def setup_accounts # rubocop:disable Metrics/MethodLength
  # Create a few test accounts
  accounts_data = [
    { username: 'alice', email: 'alice@example.com', password: 'password123' },
    { username: 'bob', email: 'bob@example.com', password: 'password123' },
    { username: 'admin', email: 'admin@example.com', password: 'password123' }
  ]

  accounts_data.each do |data|
    next if FaceCloak::Account.first(username: data[:username])

    account = FaceCloak::CreateAccount.call(account_data: data)
    role_name = (data[:username] == 'admin' ? 'admin' : 'member')
    role = FaceCloak::Role.first(name: role_name)
    account.add_system_role(role)
  end
end
