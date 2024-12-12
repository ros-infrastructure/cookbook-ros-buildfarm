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
