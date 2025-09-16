json.extract! payment, :id, :person_id, :amount, :date, :comment, :created_at, :updated_at
json.url payment_url(payment, format: :json)
