# frozen_string_literal: true

begin
  require 'hirb'
  Hirb.enable
rescue LoadError
  # hirb not installed
end
