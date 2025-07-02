#!/usr/bin/env ruby

require 'strscan'

class HtmlValidator
  VOID_ELEMENTS = %w[area base br col embed hr img input link meta param source track wbr].freeze
  SELF_CLOSING_TAGS = %w[img input br hr meta link area base col embed param source track wbr].freeze
  
  # Common Rails/ERB patterns that should be considered
  BLOCK_HELPERS = %w[form_with form_for content_tag link_to button_to].freeze
  
  def initialize
    @issues = {}
    @total_files = 0
    @files_with_issues = 0
  end
  
  def validate_directory(path = 'app/views')
    puts "🔍 Scanning HTML templates in #{path} with smart ERB awareness..."
    
    Dir.glob("#{path}/**/*.html.erb").each do |file|
      validate_file(file)
    end
    
    generate_report
  end
  
  def validate_file(file_path)
    @total_files += 1
    content = File.read(file_path)
    
    file_issues = analyze_erb_html(content)
    
    if file_issues.any?
      @files_with_issues += 1
      @issues[file_path] = file_issues
    end
  rescue => e
    @issues[file_path] = ["Error parsing file: #{e.message}"]
    @files_with_issues += 1
  end
  
  private
  
  class ErbBlock
    attr_accessor :type, :line, :content, :depth
    
    def initialize(type, line, content = nil)
      @type = type  # :if, :each, :form_with, etc.
      @line = line
      @content = content
      @depth = 0
    end
  end
  
  class HtmlTag
    attr_accessor :name, :line, :self_closing, :erb_context
    
    def initialize(name, line, self_closing = false, erb_context = nil)
      @name = name
      @line = line
      @self_closing = self_closing
      @erb_context = erb_context
    end
  end
  
  def analyze_erb_html(content)
    issues = []
    lines = content.split("\n")
    
    # Stacks to track context
    html_stack = []
    erb_stack = []
    
    lines.each_with_index do |line, idx|
      line_num = idx + 1
      
      # First, analyze ERB constructs
      analyze_erb_line(line, line_num, erb_stack)
      
      # Then analyze HTML, considering ERB context
      analyze_html_line(line, line_num, html_stack, erb_stack, issues)
    end
    
    # Check for unclosed tags at end of file
    html_stack.each do |tag|
      # Be more lenient with tags opened inside ERB blocks
      if tag.erb_context.nil? || tag.erb_context.empty?
        issues << "Line #{tag.line}: Unclosed <#{tag.name}> tag at end of file"
      elsif tag.name != 'div' # divs in ERB blocks are often intentionally split
        issues << "Line #{tag.line}: Potentially unclosed <#{tag.name}> tag (opened in ERB block)"
      end
    end
    
    issues
  end
  
  def analyze_erb_line(line, line_num, erb_stack)
    # Match ERB tags more carefully
    scanner = StringScanner.new(line)
    
    while scanner.scan_until(/<%/)
      # Find the end of the ERB tag
      erb_content = ''
      if scanner.scan_until(/%>/)
        erb_content = scanner.matched[0...-2].strip
      else
        # ERB tag continues on next line
        erb_content = scanner.rest.strip
      end
      
      # Analyze ERB content
      case erb_content
      when /^\s*=/ # Output tag
        # These don't affect structure
      when /^\s*(if|unless|case|while|until|for)\b/
        erb_stack.push(ErbBlock.new($1.to_sym, line_num, erb_content))
      when /^\s*elsif\b/
        # Continue current if block
      when /^\s*else\b/
        # Continue current block
      when /^\s*when\b/
        # Part of case statement
      when /^\s*(.*?)\.each\s*do\b/, /^\s*each\s*do\b/
        erb_stack.push(ErbBlock.new(:each, line_num, erb_content))
      when /^\s*end\b/
        erb_stack.pop unless erb_stack.empty?
      when /^\s*(form_with|form_for|form_tag|content_tag)\b/
        # These helpers often generate paired tags
        erb_stack.push(ErbBlock.new(:helper, line_num, erb_content))
      end
    end
  end
  
  def analyze_html_line(line, line_num, html_stack, erb_stack, issues)
    # Remove ERB tags for HTML analysis, but keep placeholders to maintain structure
    cleaned_line = line.gsub(/<%.*?%>/, ' ERB ')
    
    # Find all HTML tags in the line
    cleaned_line.scan(/<(\/?)(\w+)([^>]*)>/) do |slash, tag_name, attributes|
      tag_name = tag_name.downcase
      
      if slash.empty?
        # Opening tag
        if VOID_ELEMENTS.include?(tag_name)
          # Self-closing, ignore
        elsif attributes =~ /\/\s*$/
          # Explicitly self-closed
        else
          # Regular opening tag
          current_erb_context = erb_stack.map(&:type)
          html_stack.push(HtmlTag.new(tag_name, line_num, false, current_erb_context))
        end
      else
        # Closing tag
        expected = html_stack.last
        
        if expected.nil?
          issues << "Line #{line_num}: Unexpected closing tag </#{tag_name}>"
        elsif expected.name != tag_name
          # Check if it might be a valid close for an earlier tag
          matching_index = html_stack.rindex { |t| t.name == tag_name }
          
          if matching_index
            # Found a match, but tags are mis-nested
            skipped_tags = html_stack[matching_index+1..-1].map(&:name)
            if skipped_tags.any?
              issues << "Line #{line_num}: Closing </#{tag_name}> skips unclosed: #{skipped_tags.join(', ')}"
            end
            # Remove the matched tag and everything after it
            html_stack.slice!(matching_index..-1)
          else
            issues << "Line #{line_num}: Unexpected closing tag </#{tag_name}> (expected </#{expected.name}>)"
          end
        else
          # Correct closing tag
          html_stack.pop
        end
      end
    end
    
    # Special checks for common issues
    if cleaned_line =~ /<(th|td)\b[^>]*>(?!.*<\/\1)/
      # Check if tag appears to be unclosed on this line
      # But only if we're not in an ERB block and line doesn't end with ERB
      if erb_stack.empty? && !line.strip.end_with?('%>')
        tag = $1
        # Double-check it's not self-closed
        unless cleaned_line =~ /<#{tag}\b[^>]*\/>/
          issues << "Line #{line_num}: Likely unclosed <#{tag}> tag"
        end
      end
    end
    
    # Check for mismatched heading tags on same line
    if cleaned_line =~ /<h(\d)\b[^>]*>.*<\/h(\d)>/
      if $1 != $2
        issues << "Line #{line_num}: Mismatched heading tags <h#{$1}>...</h#{$2}>"
      end
    end
    
    # Check for th/td mismatches on same line
    if cleaned_line =~ /<th\b[^>]*>.*<\/td>/
      issues << "Line #{line_num}: Mismatched table tags <th>...</td>"
    elsif cleaned_line =~ /<td\b[^>]*>.*<\/th>/
      issues << "Line #{line_num}: Mismatched table tags <td>...</th>"
    end
  end
  
  def generate_report
    puts "\n📊 SMART ERB-AWARE HTML VALIDATION REPORT"
    puts "=" * 60
    puts "Total files scanned: #{@total_files}"
    puts "Files with issues: #{@files_with_issues}"
    puts "Clean files: #{@total_files - @files_with_issues}"
    puts "Success rate: #{((@total_files - @files_with_issues).to_f / @total_files * 100).round(1)}%"
    
    if @issues.any?
      puts "\n🔴 FILES WITH ISSUES (#{@files_with_issues} files):"
      puts "-" * 60
      
      # Sort by issue count (most issues first)
      sorted_issues = @issues.sort_by { |file, issues| -issues.count }
      
      # Show top 10 files with most issues
      sorted_issues.first(10).each do |file, issues|
        puts "\n#{file} (#{issues.count} issues):"
        issues.first(5).each { |issue| puts "  • #{issue}" }
        puts "  • ... and #{issues.count - 5} more issues" if issues.count > 5
      end
      
      if sorted_issues.count > 10
        puts "\n... and #{sorted_issues.count - 10} more files with issues"
      end
      
      puts "\n🎯 SUMMARY BY PRIORITY:"
      puts "-" * 40
      
      high_priority = sorted_issues.select { |file, issues| issues.count >= 10 }
      medium_priority = sorted_issues.select { |file, issues| issues.count >= 5 && issues.count < 10 }
      low_priority = sorted_issues.select { |file, issues| issues.count < 5 }
      
      puts "🔥 HIGH: #{high_priority.count} files (10+ issues)"
      puts "⚠️  MEDIUM: #{medium_priority.count} files (5-9 issues)" 
      puts "💡 LOW: #{low_priority.count} files (1-4 issues)"
      
      # Show common issue types
      all_issues = @issues.values.flatten
      issue_types = {}
      all_issues.each do |issue|
        type = case issue
               when /Unclosed <(\w+)>/ then "Unclosed <#{$1}>"
               when /Unexpected closing/ then "Unexpected closing tag"
               when /Mismatched/ then "Mismatched tags"
               when /Likely unclosed/ then "Likely unclosed tag"
               else "Other"
               end
        issue_types[type] = (issue_types[type] || 0) + 1
      end
      
      puts "\n📊 ISSUE TYPES:"
      puts "-" * 40
      issue_types.sort_by { |_, count| -count }.each do |type, count|
        puts "  #{type}: #{count}"
      end
    else
      puts "\n🎉 All HTML templates are valid!"
    end
  end
end

# Auto-run if called directly
if __FILE__ == $0
  validator = HtmlValidator.new
  validator.validate_directory(ARGV[0] || 'app/views')
end