# frozen_string_literal: true

require_relative '../../lib/erb_prism_converter'

# Serves ERB templates converted to JavaScript functions
# GET /templates/scoring.js returns all scoring templates as JS module
class TemplatesController < ApplicationController
  skip_before_action :verify_authenticity_token

  SCORING_TEMPLATES = {
    'cardsHeat' => 'app/views/scores/_cards_heat.html.erb',
    'rankHeat' => 'app/views/scores/_rank_heat.html.erb',
    'soloHeat' => 'app/views/scores/_solo_heat.html.erb',
    'tableHeat' => 'app/views/scores/_table_heat.html.erb'
  }.freeze

  def scoring
    templates = {}

    SCORING_TEMPLATES.each do |name, path|
      erb_content = File.read(Rails.root.join(path))
      converter = ErbPrismConverter.new(erb_content)
      js_code = converter.convert

      # Rename the function from 'render' to the template name
      templates[name] = js_code.sub('export function render(', "export function #{name}(")
    end

    # Build JavaScript module
    js_module = build_js_module(templates)

    render plain: js_module, content_type: 'application/javascript'
  end

  private

  def build_js_module(templates)
    output = []
    output << "// Auto-generated from ERB templates"
    output << "// DO NOT EDIT - regenerated on each request in development"
    output << ""

    # Add helper functions that templates might need
    output << "// Helper function for Rails dom_id equivalent"
    output << "function domId(object) {"
    output << "  if (typeof object === 'object' && object.id) {"
    output << "    return `heat_${object.id}`;"
    output << "  }"
    output << "  return String(object);"
    output << "}"
    output << ""

    # Add each template function
    templates.each_value do |code|
      output << code
      output << ""
    end

    # Export all templates as an object
    output << "// Export all templates"
    output << "export const templates = {"
    templates.keys.each do |name|
      output << "  #{name},"
    end
    output << "};"

    output.join("\n")
  end
end
