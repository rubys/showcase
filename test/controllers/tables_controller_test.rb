require "test_helper"

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table = tables(:one)
  end

  test "should get index" do
    get tables_url
    assert_response :success
  end

  test "should get arrange" do
    get arrange_tables_url
    assert_response :success
  end

  test "should get new" do
    get new_table_url
    assert_response :success
  end

  test "should create table" do
    assert_difference("Table.count") do
      post tables_url, params: { table: { row: 2, col: 2, number: 99, size: 10 } }
    end

    assert_redirected_to tables_url
  end

  test "should show table" do
    get table_url(@table)
    assert_response :success
  end

  test "should get edit" do
    get edit_table_url(@table)
    assert_response :success
  end

  test "should update table" do
    patch table_url(@table), params: { table: { row: 3, col: 3, number: @table.number, size: 12 } }
    assert_redirected_to table_url(@table)
  end

  test "should destroy table" do
    assert_difference("Table.count", -1) do
      delete table_url(@table)
    end

    assert_redirected_to tables_url
  end

  test "should auto-populate number field in new action" do
    # Create a few tables first (avoid existing row/col combinations)
    Table.create!(number: 5, row: 2, col: 1, size: 8)
    Table.create!(number: 10, row: 2, col: 2, size: 6)
    
    get new_table_url
    assert_response :success
    
    # Check that the response body contains the correct number value
    assert_includes response.body, 'value="11"'
  end

  test "should auto-populate number field when no tables exist" do
    # Clear all tables except fixtures
    Table.where.not(id: [@table.id, tables(:two).id]).delete_all
    
    # Get the current max number from fixtures
    max_number = Table.maximum(:number)
    expected_number = max_number + 1
    
    get new_table_url
    assert_response :success
    
    # Check that the response body contains the correct number value
    assert_includes response.body, "value=\"#{expected_number}\""
  end

  test "should update positions" do
    post update_positions_tables_url, params: { 
      table: { 
        @table.id => { row: 3, col: 3 } 
      } 
    }
    
    assert_response :success
    @table.reload
    assert_equal 3, @table.row
    assert_equal 3, @table.col
  end

  test "should reset positions" do
    post update_positions_tables_url, params: { commit: 'Reset' }
    
    assert_redirected_to tables_url
    @table.reload
    assert_nil @table.row
    assert_nil @table.col
  end
end
