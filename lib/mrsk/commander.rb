require "active_support/core_ext/enumerable"

require "mrsk/configuration"
require "mrsk/commands/app"
require "mrsk/commands/builder"
require "mrsk/commands/prune"
require "mrsk/commands/traefik"
require "mrsk/commands/registry"

class Mrsk::Commander
  attr_accessor :config_file, :destination, :verbose, :version

  def initialize(config_file: nil, destination: nil, verbose: false)
    @config_file, @destination, @verbose = config_file, destination, verbose
  end

  def config
    @config ||= \
      Mrsk::Configuration
        .create_from(config_file, destination: destination, version: cascading_version)
        .tap { |config| configure_sshkit_with(config) }
  end

  attr_accessor :specific_hosts

  def specific_primary!
    self.specific_hosts = [ config.primary_web_host ]
  end

  def specific_roles=(role_names)
    self.specific_hosts = config.roles.select { |r| role_names.include?(r.name) }.flat_map(&:hosts) if role_names.present?
  end

  def primary_host
    specific_hosts&.sole || config.primary_web_host
  end

  def hosts
    specific_hosts || config.all_hosts
  end

  def traefik_hosts
    specific_hosts || config.traefik_hosts
  end


  def app
    @app ||= Mrsk::Commands::App.new(config)
  end

  def builder
    @builder ||= Mrsk::Commands::Builder.new(config)
  end

  def traefik
    @traefik ||= Mrsk::Commands::Traefik.new(config)
  end

  def registry
    @registry ||= Mrsk::Commands::Registry.new(config)
  end

  def prune
    @prune ||= Mrsk::Commands::Prune.new(config)
  end


  def verbosity(level) 
    old_level = SSHKit.config.output_verbosity
    SSHKit.config.output_verbosity = level
    yield
  ensure
    SSHKit.config.output_verbosity = old_level
  end

  private
    def cascading_version
      version.presence || ENV["VERSION"] || `git rev-parse HEAD`.strip
    end

    # Lazy setup of SSHKit
    def configure_sshkit_with(config)
      SSHKit::Backend::Netssh.configure { |ssh| ssh.ssh_options = config.ssh_options }
      SSHKit.config.command_map[:docker] = "docker" # No need to use /usr/bin/env, just clogs up the logs
      SSHKit.config.output_verbosity = :debug if verbose
    end
end
