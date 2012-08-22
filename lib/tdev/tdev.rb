#!/usr/bin/env ruby

require "yaml"
require "readline"
require "fileutils"
require 'optparse'

env_dir = ENV["HOME"] + "/.tdev"
$env = YAML.load(File.open(env_dir))

module Tdev

  class BaseApp

    def cp_conf


      i = Time.now.to_i
      tmp_file_dir = "/tmp/antx.properties_#{i}"
      system "sed '/^ *intl.workdir *=/d' #{@conf_dir} > #{tmp_file_dir} "
      system "echo 'intl.workdir = #{$env["dev_workdir"]}' >> #{tmp_file_dir} "
      FileUtils::mv(tmp_file_dir, @dir + "/antx.properties")

    end

    def conf_need_up?

      antx_dir = "#{@dir}/antx.properties"
      return false unless File.exist?(antx_dir)

      diff = `diff #{@conf_dir} #{antx_dir}`
      ! diff.empty?
    end

    def up_conf

      return unless conf_need_up?

      puts "Really update the application configuration? (y/n)"
      update = Readline.readline('>> ')

      antx_dir = "#{@dir}/antx.properties"
      unless 'n'.eql?(update)

        FileUtils::cp(@conf_dir, @conf_dir + ".old")
        FileUtils::cp(antx_dir, @conf_dir)
      end

    end

    def config

      cp_conf
      system "cd #{@dir}/deploy; mvn clean install -Dmaven.test.skip=true -DuserProp=#{@dir}/antx.properties; cd -"
      up_conf
    end

    def build

      cp_conf
      system "cd #{@dir}/all; mvn clean install -Dmaven.test.skip=true -DuserProp=#{@dir}/antx.properties; cd -"
      up_conf
    end

    def push

      system "rsync -av --delete --progress #{@dir}/deploy #{$env["dev_addr"]}:#{@dev_appdir} --exclude 'logs' "
    end


  end

  class Standalone < BaseApp

    def initialize(dir)

      @dir = File.expand_path(dir)
      @name = /.*\/(standalone\..*)/.match(@dir)[1]
      @dev_appdir = "#{$env["dev_workdir"]}/#{@name}"

      prop_map = $env["prop_map"]
      key = @name.split("_")[0]
      config_name = prop_map[key].nil? ? @name + ".prop" : prop_map[key] + ".prop"
      @conf_dir = File.expand_path($env["config_dir"] + "/" + config_name)
    end

    def deploy

      build
      push
    end

    def deploy_cfg

      config
      push
    end
  end

  class App < BaseApp


    def initialize(dir)

      @dir = File.expand_path(dir)
      @name = /.*\/app\.(.*)/.match(@dir)[1]
      @dev_appdir = "#{$env["dev_workdir"]}/intl-#{@name}"

      prop_map = $env["prop_map"]
      key = @name.split("_")[0]
      config_name = prop_map[key].nil? ? @name + ".prop" : prop_map[key] + ".prop"
      @conf_dir = File.expand_path($env["config_dir"] + "/" + config_name)
    end

    def run

      bin_dir = "#{@dev_appdir}/deploy/bin"
      system "ssh #{$env["dev_addr"]} #{bin_dir}/killws "
      system "ssh #{$env["dev_addr"]} #{bin_dir}/startws "
    end

    def deploy

      build
      push
      run
    end

    def deploy_cfg

      config
      push
      run
    end
  end


  class Module

    def initialize(dir)

      @dir = File.expand_path(dir)
    end

    def build

      system "cd #{@dir}; mvn clean install -Dmaven.test.skip=true; cd - "
    end
  end

  class Project

    attr_accessor :mods, :apps, :stndalones
    def initialize(dir)

      @dir = File.expand_path(dir)
      @mod_list, @app_list, @standalone_list = [], [], []

      Dir.entries(@dir).each do |file|

        group = /(\w+)\..+/.match(file)

        next if group.nil? || group.size  < 2

        type = group[1]

        if "modules".eql? type

          @mod_list.push file
        elsif "app".eql? type

          @app_list.push file
        elsif "standalone".eql? type

          @standalone_list.push file
        end
      end
    end

    def init

      if @mod_list.size > 0

        puts "Module list: "
        @mod_list.each_with_index do |file, index|
          puts "[#{index}]\t#{file}"
        end

        puts "Please input the modules number you want to build and split by ' '."
        @mods = Readline.readline(">> ").chomp
      end

      if @app_list.size > 0

        puts "App list: "
        @app_list.each_with_index do |file, index|
          puts "[#{index}]\t#{file}"
        end

        puts "Please input the app number you want to build and split by ' '."
        @apps = Readline.readline(">> ").chomp
      end

      if @standalone_list.size > 0

        puts "Standalone list: "
        @standalone_list.each_with_index do |file, index|
          puts "[#{index}]\t#{file}"
        end

        puts "Please input the standalone number you want to build and split by ' '."
        @standalones = Readline.readline(">> ").chomp
      end

    end

    def build

      unless @mods.nil? || @mods.empty?

        @mods.split("\s").each do |num|

          task_dir = @dir + "/" + @mod_list[num.to_i]
          Tdev::Module.new(task_dir).build
        end
      end

      unless @apps.nil?  || @apps.empty?

        @apps.split("\s").each do |num|

          task_dir = @dir + "/" + @app_list[num.to_i]
          Tdev::App.new(task_dir).build
        end
      end

      unless @standalones.nil?  || @standlaones.empty?

        @standalones.split("\s").each do |num|

          task_dir = @dir + "/" + @standalone_list[num.to_i]
          Tdev::Standalone.new(task_dir).build
        end
      end
    end

    def deploy

      init
      build

      unless @apps.nil?  || @apps.empty?

        @apps.split("\s").each do |num|

          task_dir = @dir + "/" + @app_list[num.to_i]
          Tdev::App.new(task_dir).deploy
        end
      end

      unless @standalones.nil?  || @standaones.empty?

        @standalones.split("\s").each do |num|

          task_dir = @dir + "/" + @standalone_list[num.to_i]
          Tdev::Standalone.new(task_dir).deploy
        end
      end
    end

  end
end

base_dir = File.expand_path($env['workdir'])

dir = Dir.pwd

group = /#{base_dir}\/?([^\/]*)\/?([^\/]*)/.match(dir)

if group.nil?

	$mod = 'other'
elsif !group[2].nil? && !group[2].empty?

    grp = /(\w+)\..+/.match(group[2])

    unless grp.nil? || grp.size  < 2

      type = grp[1]

      if "modules".eql? type

      	$mod = 'module'
      elsif "app".eql? type

      	$mod = 'app'
      elsif "standalone".eql? type

        $mod = 'standalone'
      end
    end
elsif !group[1].nil? && !group[1].empty?

  $mod = 'project'
else

	$mod = 'other'
end

puts "Current mod is \"#{$mod}\""

module_op = OptionParser.new do |opts|

  opts.banner = 'Here is help messages of the tdev tool.'

  opts.on do
    Tdev::Module.new(dir).build
  end

  opts.on('build', 'build module') do
    Tdev::Module.new(dir).build
  end

end

app_op = OptionParser.new do |opts|

  opts.banner = 'Here is help messages of the tdev tool.'

  opts.on do
    Tdev::App.new(dir).deploy
  end

  opts.on('cp-conf', 'copy the config to app') do
    Tdev::App.new(dir).cp_conf
  end

  opts.on('config', 'config app') do
    Tdev::App.new(dir).config
  end

  opts.on('build', 'build app') do
    Tdev::App.new(dir).build
  end

  opts.on('push', 'push app to dev') do
    Tdev::App.new(dir).push
  end

  opts.on('run', 'run app') do
    Tdev::App.new(dir).run
  end

  opts.on('deploy', 'deploy app') do
    Tdev::App.new(dir).deploy
  end

  opts.on('deploy-cfg', 'deploy app only config') do
    Tdev::App.new(dir).deploy_cfg
  end

end

standalone_op = OptionParser.new do |opts|

  opts.banner = 'Here is help messages of the tdev tool.'

  opts.on do
    Tdev::Standalone.new(dir).deploy
  end

  opts.on('cp-conf', 'copy the config to standalone') do
    Tdev::Standalone.new(dir).cp_conf
  end

  opts.on('config', 'config standalone') do
    Tdev::Standaone.new(dir).config
  end

  opts.on('build', 'build standalone') do
    Tdev::Standalone.new(dir).build
  end

  opts.on('push', 'push app to standalone') do
    Tdev::Standalone.new(dir).push
  end

  opts.on('deploy', 'deploy standalone') do
    Tdev::Standalone.new(dir).deploy
  end

  opts.on('deploy-cfg', 'deploy standalone only config') do
    Tdev::Standalone.new(dir).deploy_cfg
  end

end

proj_op = OptionParser.new do |opts|

  opts.banner = 'Here is help messages of the tdev tool.'

  opts.on do
    Tdev::Project.new(dir).deploy
  end

  opts.on('init', 'init project') do
    Tdev::Project.new(dir).init
  end

  opts.on('build', 'build project') do
    Tdev::Project.new(dir).build
  end

  opts.on('deploy', 'deploy project') do
    Tdev::Project.new(dir).deploy
  end

end

case $mod 
when 'project'
  proj_op.parse!
when 'app'
  app_op.parse!
when 'standalone'
  standalone_op.parse!
when 'module'
  module_op.parse!
when 'other'
  puts 'hello, teafly!'
end
