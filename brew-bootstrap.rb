#!/usr/bin/env ruby

def usage
  usage = %{
    Usage:
    ruby #{$0}[ preset][ --dry-run]
    ruby #{$0} brew[ preset]
    ruby #{$0} brew life preset dev
    ruby #{$0} cask
      (the same way)
    ruby #{$0} candidate
  }
  puts usage
end

require 'yaml'
begin
  require 'puttin/colorize'
rescue LoadError
  require_relative 'colorize'
end


CONFIG = YAML.load(File.read("#{__dir__}/brew.yml"))
ENV['HOMEBREW_NO_AUTO_UPDATE'] = '1'

def preset
  brew
  cask
end

def brew(rest_argv = [])
  categories = []
  case rest_argv.count
  when 0
    categories << brew_preset
  else
    preset_key = 'preset'
    if rest_argv.include?(preset_key)
      categories << brew_preset
      rest_argv.delete(preset_key)
    end
    categories << rest_argv
  end

  categories = categories.flatten.uniq
  puts "install brew category #{categories.join(' ')}".light_blue
  brew_categories(categories)
end

def brew_preset
  CONFIG['brew']['preset']
end

def brew_categories(categories)
  items = []
  all = CONFIG['brew']['categories']
  categories.each { |c|
    unless all.has_key?(c)
      invalid_arg_exit {
        puts "unknown category #{c}"
      }
    end

    items << all[c]
  }

  items = items.flatten.uniq
  brew_items(items)
end

def brew_items(items)
  items.each { |item|
    if brew_item_exist?(item)
      puts "#{item} already installed, skip…".green
      next
    end
    run("brew install #{item}")
    $stdout.flush
  }
end

$lazy_exist_brew_items = nil
def exist_brew_items
  return $lazy_exist_brew_items unless $lazy_exist_brew_items.nil?
  $lazy_exist_brew_items = `brew list --formula -1`.split("\n")
end

def brew_item_exist?(item)
  # `brew ls --versions #{item} > /dev/null`
  # return $?.to_i == 0
  return exist_brew_items.include?(item)
end

def cask(rest_argv = [])
  categories = []
  case rest_argv.count
  when 0
    categories << cask_preset
  else
    preset_key = 'preset'
    if rest_argv.include?(preset_key)
      categories << cask_preset
      rest_argv.delete(preset_key)
    end
    categories << rest_argv
  end

  categories = categories.flatten.uniq
  puts "install cask category #{categories.join(' ')}".light_blue
  cask_categories(categories)
end

def cask_preset
  CONFIG['cask']['preset']
end

def cask_categories(categories)
  items = []
  all = CONFIG['cask']['categories']
  categories.each { |c|
    unless all.has_key?(c)
      invalid_arg_exit {
        puts "unknown category #{c}"
      }
    end

    items << all[c]
  }

  items = items.flatten.uniq
  cask_items(items)
end

def cask_items(items)
  items.each { |item|
    if cask_item_exist?(item)
      puts "cask #{item} already installed, skip…".green
      next
    end

    case cask_item_app_exist?(item)
    when nil
      puts "unable to detect if cask #{item} is installed or not".red
      next
    when true
      puts "cask #{item} 's App already installed, skip…".yellow
      next
    when false
      run("brew install --cask #{item}")
    end
    $stdout.flush
  }
end

CASK_INFO_CACHE = Hash.new
def cask_info(item)
  cask_item = item
  relative_cask_formula_path = "#{__dir__}/#{item}"
  if File.exist?(relative_cask_formula_path)
    cask_item = relative_cask_formula_path
    # puts "checking relative cask formula #{cask_item}".gray
  end
  if CASK_INFO_CACHE.include?(cask_item)
    return CASK_INFO_CACHE[cask_item]
  end
  cask_info = `brew info --cask #{cask_item}`
  CASK_INFO_CACHE[cask_item] = cask_info
  return cask_info
end

def cask_name(item)
  cask_info_result = cask_info(item)
  return item if cask_info_result.empty?
  cask_name = cask_info_result.lines.first.split(':').first
  return cask_name
end

$lazy_exist_cask_items = nil
def exist_cask_items
  return $lazy_exist_cask_items unless $lazy_exist_cask_items.nil?
  $lazy_exist_cask_items = `brew list --cask -1`.split("\n")
end

def cask_item_exist?(item)
  return true if exist_cask_items.include?(item.split('/').last)

  name = cask_name(item)
  return exist_cask_items.include?(name)
end

# try to find the app. it doesn't support pkg e.g., 'microsoft-office'
APP_NAME_REGEX = /Artifacts\n(.+)\s\(App\)/
USER_HOME = File.expand_path('~')
def cask_item_app_exist?(item)
  cask_info_result = cask_info(item)
  match = cask_info_result.match(APP_NAME_REGEX)
  return nil if match.nil?
  app_name = match[1]

  mdfind = `mdfind -name '#{app_name}'`
  return true unless mdfind.empty?
  
  # maybe mdutil is off
  return true if File.exist?("/Applications/#{app_name}")
  return true if File.exist?("#{USER_HOME}/Applications/#{app_name}")

  false
end

def brew_dependencies
  deps_result = `brew deps --installed`
  dependencies = deps_result.lines.map{|line| line.split(':').last.split(' ')}.flatten.uniq
  dependencies
end

def brew_candidate
  puts "brew candidates:".green
  dependencies = brew_dependencies
  all_items = []
  brew_categories = CONFIG['brew']['categories']
  brew_categories.each_value { |c|
    all_items << c
  }
  all_items = all_items.flatten.uniq

  exist_brew_items.each { |item|
    puts item if !all_items.include?(item) && !dependencies.include?(item)
  }
end

def cask_candidate
  all_items = []
  cask_categories = CONFIG['cask']['categories']
  cask_categories.each_value { |c|
    all_items << c
  }
  all_items = all_items.flatten.uniq
  lazy_taps_names = all_items.map { |item|
    next nil unless item.include? '/'
    item
  }.compact.lazy.map { |item|
    cask_name(item)
  }
  puts "cask candidates:".green
  exist_cask_items.each { |item|
    match = all_items.include?(item) || lazy_taps_names.include?(item)
    next if match
    puts item
  }
end

INVALID = 'Invalid Arguments'
def invalid_arg_exit
  STDERR.puts INVALID.red
  yield if block_given?
  exit false
end

def run(cmd, colorize = true)
  if DRY_RUN
    puts cmd.gray
    return
  end

  # https://github.com/Homebrew/brew/blob/36dbad3922ad984f7c396a9757fe8ae9750c44b0/Library/Homebrew/utils/tty.rb#L66
  puts `#{colorize ? 'HOMEBREW_COLOR=1 ' : ''}#{cmd}`
end

def main(argv)
  case argv.count
  when 0
    preset
  else
    case argv.first
    when 'preset'
      preset
    when 'brew'
      brew(argv.drop(1))
    when 'cask'
      cask(argv.drop(1))
    when 'candidate'
      brew_candidate
      cask_candidate
    else
      invalid_arg_exit {
        usage
      }
    end
  end
end

def ensure_brew_installed
  `which brew > /dev/null`
  return if $?.to_i == 0
  puts "brew is not installed yet".red
  exit 128
end

ensure_brew_installed
argv = ARGV
DRY_RUN = argv.include?('--dry-run')
argv.delete('--dry-run')
main(argv)
