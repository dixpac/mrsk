require "mrsk/cli/base"

class Mrsk::Cli::App < Mrsk::Cli::Base
  desc "boot", "Boot app on servers (or start them if they've already been booted)"
  def boot
    MRSK.config.roles.each do |role|
      on(role.hosts) do |host|
        begin
          execute *MRSK.app.run(role: role.name)
        rescue SSHKit::Command::Failed => e
          if e.message =~ /already in use/
            error "Container with same version already deployed on #{host}, starting that instead"
            execute *MRSK.app.start, host: host
          else
            raise
          end
        end
      end
    end
  end
  
  desc "start", "Start existing app on servers (use --version=<git-hash> to designate specific version)"
  option :version, desc: "Defaults to the most recent git-hash in local repository"
  def start
    if (version = options[:version]).present?
      on(MRSK.hosts) { execute *MRSK.app.start(version: version) }
    else
      on(MRSK.hosts) { execute *MRSK.app.start, raise_on_non_zero_exit: false }
    end
  end
  
  desc "stop", "Stop app on servers"
  def stop
    on(MRSK.hosts) { execute *MRSK.app.stop, raise_on_non_zero_exit: false }
  end
  
  desc "details", "Display details about app containers"
  def details
    on(MRSK.hosts) { |host| puts_by_host host, capture_with_info(*MRSK.app.info) }
  end
  
  desc "exec [CMD]", "Execute a custom command on servers"
  option :run, type: :boolean, default: false, desc: "Start a new container to run the command rather than reusing existing"
  def exec(cmd)
    runner = options[:run] ? :run_exec : :exec
    on(MRSK.hosts) { |host| puts_by_host host, capture_with_info(*MRSK.app.send(runner, cmd)) }
  end

  desc "console", "Start Rails Console on primary host (or specific host set by --hosts)"
  def console
    run_locally do
      puts "Launching Rails console on #{MRSK.primary_host}..."
      exec MRSK.app.console(host: MRSK.primary_host)        
    end
  end

  desc "bash", "Start a bash session on primary host (or specific host set by --hosts)"
  def bash
    run_locally do
      puts "Launching bash session on #{MRSK.primary_host}..."
      exec MRSK.app.bash(host: MRSK.primary_host)        
    end
  end

  desc "runner [EXPRESSION]", "Execute Rails runner with given expression"
  def runner(expression)
    on(MRSK.hosts) { |host| puts_by_host host, capture_with_info(*MRSK.app.exec("bin/rails", "runner", "'#{expression}'")) }
  end

  desc "containers", "List all the app containers currently on servers"
  def containers
    on(MRSK.hosts) { |host| puts_by_host host, capture_with_info(*MRSK.app.list_containers) }
  end

  desc "current", "Return the current running container ID"
  def current
    on(MRSK.hosts) { |host| puts_by_host host, capture_with_info(*MRSK.app.current_container_id) }
  end
  
  desc "logs", "Show last 100 log lines from app on servers"
  option :since, aliases: "-s", desc: "Show logs since timestamp (e.g. 2013-01-02T13:23:37Z) or relative (e.g. 42m for 42 minutes)"
  option :lines, type: :numeric, aliases: "-n", desc: "Number of log lines to pull from each server"
  option :grep, aliases: "-g", desc: "Show lines with grep match only (use this to fetch specific requests by id)"
  def logs
    # FIXME: Catch when app containers aren't running

    since = options[:since]
    lines = options[:lines]
    grep  = options[:grep]

    on(MRSK.hosts) do |host|
      begin
        puts_by_host host, capture_with_info(*MRSK.app.logs(since: since, lines: lines, grep: grep))
      rescue SSHKit::Command::Failed
        puts_by_host host, "Nothing found"
      end
    end
  end
  
  desc "remove", "Remove app containers and images from servers"
  option :only, default: "", desc: "Use 'containers' or 'images'"
  def remove
    case options[:only]
    when "containers"
      on(MRSK.hosts) { execute *MRSK.app.remove_containers }
    when "images"
      on(MRSK.hosts) { execute *MRSK.app.remove_images }
    else
      on(MRSK.hosts) { execute *MRSK.app.remove_containers }
      on(MRSK.hosts) { execute *MRSK.app.remove_images }
    end
  end
end
