# frozen_string_literal: true

# Persist statesman transitions through Active Record (the default adapter is in-memory).
Statesman.configure do
	storage_adapter(Statesman::Adapters::ActiveRecord)
end
