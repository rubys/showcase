#!/usr/bin/env ruby

class HtmlValidator
  VOID_ELEMENTS = %w[area base br col embed hr img input link meta param source track wbr].freeze
  
  def initialize
    @issues = {}
    @total_files = 0
    @files_with_issues = 0
  end
  
  def validate_directory(path = 'app/views')
    puts "🔍 Scanning HTML templates in #{path}..."
    
    Dir.glob("#{path}/**/*.html.erb").each do |file|
      validate_file(file)
    end
    
    generate_report
  end
  
  def validate_file(file_path)
    @total_files += 1
    content = File.read(file_path)
    file_issues = scan_for_issues(content)
    
    if file_issues.any?
      @files_with_issues += 1
      @issues[file_path] = file_issues
    end
  end
  
  private
  
  def scan_for_issues(content)
    issues = []
    lines = content.split("\n")
    
    lines.each_with_index do |line, idx|
      line_num = idx + 1
      
      # Check for unclosed table elements
      if line.match(/<th\b[^>]*>[^<]*$/) && !line.include?('</th>')
        issues << "Line #{line_num}: Unclosed <th> tag"
      end
      
      if line.match(/<td\b[^>]*>[^<]*$/) && !line.include?('</td>')
        issues << "Line #{line_num}: Unclosed <td> tag"  
      end
      
      # Check for mismatched heading tags
      if line.match(/<h(\d)\b[^>]*>.*<\/h(\d)>/) 
        open_level = $1
        close_level = $2
        if open_level != close_level
          issues << "Line #{line_num}: Mismatched heading tags <h#{open_level}>...</h#{close_level}>"
        end
      end
      
      # Check for mismatched table tags
      if line.match(/<th\b[^>]*>.*<\/td>/)
        issues << "Line #{line_num}: Mismatched table tags <th>...</td>"
      end
      
      if line.match(/<td\b[^>]*>.*<\/th>/)
        issues << "Line #{line_num}: Mismatched table tags <td>...</th>"
      end
      
      # Check for unclosed div tags (simple case)
      if line.match(/<div\b[^>]*>[^<]*$/) && !line.include?('</div>')
        issues << "Line #{line_num}: Potentially unclosed <div> tag"
      end
      
      # Check for unclosed list items
      if line.match(/<li\b[^>]*>[^<]*$/) && !line.include?('</li>')
        issues << "Line #{line_num}: Unclosed <li> tag"
      end
    end
    
    issues
  end
  
  def generate_report
    puts "\n📊 HTML VALIDATION REPORT"
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
      
      sorted_issues.each do |file, issues|
        puts "\n#{file} (#{issues.count} issues):"
        issues.each { |issue| puts "  • #{issue}" }
      end
      
      puts "\n🎯 RECOMMENDED PRIORITY ORDER:"
      puts "-" * 40
      
      high_priority = sorted_issues.select { |file, issues| issues.count >= 10 }
      medium_priority = sorted_issues.select { |file, issues| issues.count >= 5 && issues.count < 10 }
      low_priority = sorted_issues.select { |file, issues| issues.count < 5 }
      
      if high_priority.any?
        puts "\n🔥 HIGH PRIORITY (#{high_priority.count} files with 10+ issues):"
        high_priority.each { |file, issues| puts "  #{issues.count} issues: #{file}" }
      end
      
      if medium_priority.any?
        puts "\n⚠️  MEDIUM PRIORITY (#{medium_priority.count} files with 5-9 issues):"
        medium_priority.each { |file, issues| puts "  #{issues.count} issues: #{file}" }
      end
      
      if low_priority.any?
        puts "\n💡 LOW PRIORITY (#{low_priority.count} files with 1-4 issues):"
        low_priority.each { |file, issues| puts "  #{issues.count} issues: #{file}" }
      end
      
      generate_fix_commands(high_priority)
    else
      puts "\n🎉 All HTML templates are valid!"
    end
  end
  
  def generate_fix_commands(high_priority_files)
    return if high_priority_files.empty?
    
    puts "\n🔧 QUICK FIX COMMANDS:"
    puts "-" * 40
    puts "# Fix high priority files first:"
    
    high_priority_files.first(5).each do |file, issues|
      puts "bin/rails runner \"HtmlFixer.new('#{file}').fix_all\""
    end
    
    puts "\n# Or fix all high priority files:"
    puts "bin/rails runner \"HtmlFixer.fix_high_priority\""
  end
end

# Auto-run if called directly
if __FILE__ == $0
  validator = HtmlValidator.new
  validator.validate_directory(ARGV[0] || 'app/views')
end