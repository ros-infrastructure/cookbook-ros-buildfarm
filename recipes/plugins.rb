include_recipe 'jenkins::plugin_manager'

template "/var/lib/jenkins/plugins.txt" do
  source "plugins.txt.erb"
  mode "0644"
  owner "jenkins"
  group "jenkins"
  variables(
    plugins: node['ros_buildfarm']['jenkins']['plugins']
  )
end

execute 'install-jenkins-plugins' do
  # Refer to https://github.com/jenkinsci/plugin-installation-manager-tool for details about tool usage.
  command %w[
             java -jar /usr/local/jenkins/jars/jenkins-plugin-manager.jar
             --plugin-download-directory /var/lib/jenkins/plugins
             --plugin-file /var/lib/jenkins/plugins.txt
             --latest=false
            ]
  user "jenkins"
  notifies :restart, 'service[jenkins]', :delayed
end

# Remove plugins that were required previously but are not now. By:
# * Listing all plugins (.jpi files) in the plugin directories
# * Delete the plugins (.jpi file) stated in ['jenkins']['remove_plugins']
plugin_remove_filter = node.default['ros_buildfarm']['jenkins']['remove_plugins'].map! {|e| "#{e}.jpi"}.join("|")
execute "ls /var/lib/jenkins/plugins | grep -E \"#{plugin_remove_filter}\" | xargs -r rm" do
  # If there are no plugins, then we don't need to remove anything
  only_if { ::Dir.exist? '/var/lib/jenkins/plugins/' }
end
