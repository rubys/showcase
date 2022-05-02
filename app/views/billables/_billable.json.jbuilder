json.extract! billable, :id, :type, :name, :amount, :order, :created_at, :updated_at
json.url billable_url(billable, format: :json)
