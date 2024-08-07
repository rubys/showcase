require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entry = entries(:one)
    @primary = people(:Kathryn)
  end

  test "should get index" do
    get entries_url
    assert_response :success
  end

  test "should get new" do
    get new_entry_url(params: { primary: @primary.id })
    assert_response :success
  end

  test "should create entry" do
    partner = people(:Arthur)

    entries = %w(Closed Open Multi).map do |category|
      [category, Dance.all.map do |dance|
        [dance.id, 1] if !!dance.heat_length ^ (category == 'Multi')
      end.compact.to_h]
    end.to_h

    assert_difference("Entry.count") do
      post entries_url, params: { entry: { primary: @primary.id, partner: partner.id, entries: entries, age: ages(:B1).id, follow_id: @entry.follow_id, lead_id: @entry.lead_id, level: @entry.level_id } }
    end

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], '6 heats successfully created.'
  end

  test "should merge entry" do
    partner = people(:Arthur)

    entries = %w(Closed Open Multi).map do |category|
      [category, Dance.all.map do |dance|
        [dance.id, 1] if !!dance.heat_length ^ (category == 'Multi')
      end.compact.to_h]
    end.to_h

    assert_difference("Entry.count", 0) do
      post entries_url, params: { entry: { primary: @primary.id, partner: partner.id, entries: entries, age: @entry.age_id, follow_id: @entry.follow_id, lead_id: @entry.lead_id, level: @entry.level_id } }
    end

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], '6 heats successfully created.'
  end

  test "should show entry" do
    get entry_url(@entry)
    assert_response :success
  end

  test "should get edit" do
    get edit_entry_url(@entry, params: { primary: @primary.id })
    assert_response :success
  end

  test "should update entry" do
    partner = people(:Arthur)

    entries = %w(Closed Open Multi).map do |category|
      [category, Dance.all.map do |dance|
        [dance.id, 1] if !!dance.heat_length ^ (category == 'Multi')
      end.compact.to_h]
    end.to_h

    patch entry_url(@entry), params: { entry: { primary: @primary.id, partner: partner.id, entries: entries, age: @entry.age_id, follow_id: @entry.follow_id, lead_id: @entry.lead_id, level: @entry.level_id } }
    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], '7 heats changed.'
  end

  test "should scratch entry" do
    delete entry_url(@entry, params: { primary: @primary.id })
    @entry.reload
    assert @entry.heats.all? {|heat| heat.number <= 0}

    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], '2 heats scratched.'
  end
end
