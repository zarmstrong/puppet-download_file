Puppet::Parser::Functions::newfunction(:download_jenkins_file, :type => :rvalue, :doc =>
  "Downloads the latest Stable Build artifact from a jenkins project into a file server mount on the server,
   unless it's already there, and returns the appropriate puppet:/// URL for the puppet client to use.

       file { '/tmp/test':
         ensure => file,
         source => download_jenkins_file('file_mountpoint', 'path/in/mountpoint/here[optional, leave blank for none]', 'http://jenkinsserver/job/jobname','pattern-of-filename-to-match','jenkinsuser','jenkinspassword')
       }

 ") do |args|
  require 'digest/sha1'
  require 'fileutils'
  require 'open-uri'
  require 'puppet/file_serving/configuration'

  self.fail "Plugins mount point is not supported" if args[0] == 'plugins'

  mount = args[0]
  path = args[1]
  url = args[2]
  filename = args[3]
  if args.length == 6 then
    httpuser = args[4]
    httppass = args[5]
    httpoptions = 1
  end

  uri = URI.parse(url + "/lastStableBuild/api/json?tree=artifacts[fileName,relativePath]")

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.request_uri)

  if httpoptions then
  request.basic_auth httpuser, httppass
  end

  response = http.request(request)
  the_filename=""
  if response.code == "200"
    result = JSON.parse(response.body)
    if /#{filename}/ =~ result.to_s then
      result["artifacts"].each do |doc|
        if /#{filename}/ =~ doc["relativePath"] then
          url = url + "/lastStableBuild/artifact/" + doc["relativePath"]
          the_filename = doc["fileName"]
          break
        end
      end
    end
  end

  if mount == 'modules' then
    module_name, path = path.split('/', 2)
    mod = environment.module(module_name)
    base_dir = mod.file(nil)
    file_prefix = 'puppet'
  elsif Puppet.settings[:name] == 'apply' and ::FileTest.directory?('/vagrant')
    # Assume we're in a Vagrant box
    base_dir = '/vagrant/.download_file-cache'
    file_prefix = 'file'
    mount = 'vagrant/.download_file-cache'
  elsif Puppet.settings[:name] == 'apply'
    # Assume we're on a dev server
    base_dir = '/var/cache/download_file'
    file_prefix = 'file'
    mount = 'var/cache/download_file'
  else
    mnt = Puppet::FileServing::Configuration.configuration.find_mount(mount, environment)
    if not mnt then
      self.fail "No mount found named #{mount}"
    end
    base_dir = mnt.path(compiler.node)
    file_prefix = 'puppet'
  end
  file_name = ::File.join(base_dir, path, the_filename)

  unless ::FileTest.exist?(file_name) then
    Puppet.info "Downloading #{url} to #{file_name}"
    parent_dir = ::File.dirname(file_name)
    ::FileUtils.mkdir_p(parent_dir) unless ::FileTest.exist?(parent_dir)
    ::File.open(file_name, 'wb') do |file|
      if (httpoptions == 1)
        open(url, 'rb', :http_basic_authentication => [httpuser,httppass]) do |stream|
        until stream.eof?
          # StringIO doesn't support :readpartial
          if stream.respond_to?(:readpartial)
            file.write(stream.readpartial(1024))
          else
            file.write(stream.read(1024))
          end
        end
      end
      else
        open(url, 'rb') do |stream|
          until stream.eof?
            # StringIO doesn't support :readpartial
            if stream.respond_to?(:readpartial)
              file.write(stream.readpartial(1024))
            else
              file.write(stream.read(1024))
            end
          end
        end
      end
    end
  end

  served_filename =  ::File.join(path, the_filename)
  "#{file_prefix}:///#{mount}/#{served_filename}"
end
