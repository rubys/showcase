# frozen_string_literal: true

require_relative '../../lib/erb_prism_converter'

# Serves ERB templates converted to JavaScript functions
# GET /templates/scoring.js returns all scoring templates as JS module
class TemplatesController < ApplicationController
  skip_before_action :verify_authenticity_token

  SCORING_TEMPLATES = {
    'heat' => 'app/views/scores/heat.html.erb',
    'heatlist' => 'app/views/scores/heatlist.html.erb',
    'heatHeader' => 'app/views/scores/_heat_header.html.erb',
    'infoBox' => 'app/views/scores/_info_box.html.erb',
    'navigationFooter' => 'app/views/scores/_navigation_footer.html.erb',
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
    output << "// Path helper stubs for generating URLs (will be intercepted by SPA navigation)"
    output << "function judge_heat_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/scores/${judgeId}/heat/${options.heat}?style=${options.style || 'radio'}`;"
    output << "}"
    output << "function judge_heat_slot_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/scores/${judgeId}/heat/${options.heat}/slot/${options.slot}?style=${options.style || 'radio'}`;"
    output << "}"
    output << "function recording_heat_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/recordings/${judgeId}/heat/${options.heat}`;"
    output << "}"
    output << "function recording_heat_slot_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/recordings/${judgeId}/heat/${options.heat}/slot/${options.slot}`;"
    output << "}"
    output << "function person_path(person) {"
    output << "  return `/people/${person.id || person}`;"
    output << "}"
    output << "function sort_scores_path() {"
    output << "  return '/scores/sort';"
    output << "}"
    output << "function show_assignments_person_path(person) {"
    output << "  return `/people/${person.id || person}/show_assignments`;"
    output << "}"
    output << "function post_score_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/scores/${judgeId}/post`;"
    output << "}"
    output << "function post_feedback_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/scores/${judgeId}/post-feedback`;"
    output << "}"
    output << "function update_rank_path(options) {"
    output << "  const judgeId = (typeof options.judge === 'object') ? options.judge.id : options.judge;"
    output << "  return `/scores/${judgeId}/post`;"
    output << "}"
    output << "function start_heat_event_index_path() {"
    output << "  return `/event/start_heat`;"
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
