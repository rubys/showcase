require "test_helper"
require "tempfile"

class TemplatesControllerTest < ActionDispatch::IntegrationTest
  test "scoring templates generate valid JavaScript syntax" do
    get scoring_templates_path
    assert_response :success
    assert_match /javascript/, response.media_type

    # Write the generated JS to a temporary file
    Tempfile.create(['scoring', '.mjs']) do |f|
      f.write(response.body)
      f.flush

      # Use Node.js to validate syntax
      error_output = `node --check #{f.path} 2>&1`
      result = $?.success?

      # If syntax check fails, show the actual error
      unless result
        flunk "Generated JavaScript has syntax errors:\n#{error_output}"
      end
    end
  end

  test "scoring templates export expected functions" do
    get scoring_templates_path
    assert_response :success

    # Check for expected exports
    assert_match /export function soloHeat\(data\)/, response.body
    assert_match /export function rankHeat\(data\)/, response.body
    assert_match /export function tableHeat\(data\)/, response.body
    assert_match /export function cardsHeat\(data\)/, response.body
  end

  test "scoring templates include domId helper" do
    get scoring_templates_path
    assert_response :success

    # Check for helper function
    assert_match /function domId\(object\)/, response.body
  end
end
