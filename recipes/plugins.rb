include_recipe 'jenkins::plugin_manager'

plugins_txt = '/var/lib/jenkins/plugins.txt'
# Copy of the plugins.txt that the plugin manager last installed successfully
installed_plugins_txt = '/var/lib/jenkins/plugins.txt.installed'

template plugins_txt do
  source "plugins.txt.erb"
  mode "0644"
  owner "jenkins"
  group "jenkins"
  variables(
    plugins: node['ros_buildfarm']['jenkins']['plugins']
  )
end

# Read at compile time, before this run updates the copy. Empty names are
# dropped because a plugin directory is deleted recursively below.
previously_installed = if ::File.exist?(installed_plugins_txt)
                         ::File.readlines(installed_plugins_txt).map { |l| l.split(':').first.to_s.strip }.reject(&:empty?)
                       else
                         []
                       end

# Plugins dropped from the attributes since the last install, plus leftovers
# removed before plugins.txt.installed existed. Deleted before the install, so
# that the install downloads again any of them still needed as a dependency.
wanted_plugins = node['ros_buildfarm']['jenkins']['plugins'].keys
removed_plugins = ((previously_installed - wanted_plugins) |
                   node['ros_buildfarm']['jenkins']['remove_plugins']) - wanted_plugins

removed_plugins.each do |plugin|
  %W(#{plugin}.jpi #{plugin}.jpi.disabled).each do |f|
    file "/var/lib/jenkins/plugins/#{f}" do
      action :delete
      notifies :restart, 'service[jenkins]', :delayed
    end
  end
  # No restart here: a plugin that has only this directory was never loaded
  # from a .jpi, and the install below restarts anyway because the list changed.
  directory "/var/lib/jenkins/plugins/#{plugin}" do
    recursive true
    action :delete
  end
end

# Comparing with the copy written after a successful install, instead of
# subscribing to the template, retries an install that failed in a previous run.
execute 'install-jenkins-plugins' do
  # Refer to https://github.com/jenkinsci/plugin-installation-manager-tool for details about tool usage.
  command %W[
             java -jar /usr/local/jenkins/jars/jenkins-plugin-manager.jar
             --plugin-download-directory /var/lib/jenkins/plugins
             --plugin-file #{plugins_txt}
             --latest=false
            ]
  user "jenkins"
  not_if do
    ::File.exist?(installed_plugins_txt) &&
      ::FileUtils.compare_file(plugins_txt, installed_plugins_txt)
  end
  notifies :create, "file[#{installed_plugins_txt}]", :immediately
  notifies :restart, 'service[jenkins]', :delayed
end

file installed_plugins_txt do
  content lazy { ::File.read(plugins_txt) }
  mode '0644'
  owner 'jenkins'
  group 'jenkins'
  action :nothing
end
